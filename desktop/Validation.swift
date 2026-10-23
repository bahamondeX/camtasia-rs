import Foundation
import AVFoundation

@main
@MainActor
struct Validation {
    static func main() async {
        do {
            try await run()
        } catch {
            FileHandle.standardError.write(Data("FAIL: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    static func run() async throws {
        guard CommandLine.arguments.count == 4 else { throw EditorFailure(message: "Usage: validate INPUT OUTPUT PROJECT") }
        let input = URL(fileURLWithPath: CommandLine.arguments[1])
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        let projectPath = CommandLine.arguments[3]
        let core = CoreBridge()
        let imported = try core.execute(await MediaEngine.importCommand(input))
        guard let media = imported.media.first else { throw EditorFailure(message: "Import failed") }
        let added = try core.execute(["command": "timeline.add_clip", "media_id": media.id, "position": EditorTime(seconds: 0).json])
        guard let clip = added.track.clips.first else { throw EditorFailure(message: "Add failed") }
        _ = try core.execute(["command": "timeline.trim_clip", "clip_id": clip.id,
                              "source_start": EditorTime(seconds: 1).json, "duration": EditorTime(seconds: 2).json])
        _ = try core.execute(["command": "project.save", "path": projectPath])
        let reopened = CoreBridge()
        let project = try reopened.execute(["command": "project.open", "path": projectPath])
        try await MediaEngine.export(project, to: output)
        let asset = AVURLAsset(url: output)
        let duration = try await asset.load(.duration)
        guard abs(duration.seconds - 2) < 0.05,
              let video = try await asset.loadTracks(withMediaType: .video).first else { throw EditorFailure(message: "Invalid exported duration or video") }
        let reader = try AVAssetReader(asset: asset)
        let trackOutput = AVAssetReaderTrackOutput(track: video, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(trackOutput)
        guard reader.startReading() else { throw reader.error ?? EditorFailure(message: "Decoder failed to start") }
        var frames = 0
        while trackOutput.copyNextSampleBuffer() != nil { frames += 1 }
        guard reader.status == .completed, frames == 60 else { throw reader.error ?? EditorFailure(message: "Expected 60 decoded frames, got \(frames)") }
        print("PASS: Rust import/add/trim/save/reopen; native H.264 MP4 export; duration \(duration.seconds)s; \(frames) decoded frames")
    }
}
