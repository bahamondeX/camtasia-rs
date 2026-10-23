import Foundation
import AVFoundation

@MainActor
enum MediaEngine {
    static func importCommand(_ url: URL) async throws -> [String: Any] {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        guard duration.isNumeric, duration.seconds > 0,
              let video = try await asset.loadTracks(withMediaType: .video).first else {
            throw EditorFailure(message: "A finite video track is required")
        }
        let size = try await video.load(.naturalSize)
        let rate = try await video.load(.nominalFrameRate)
        return ["command": "media.import", "path": url.path,
                "duration": EditorTime(duration).json, "width": Int32(size.width),
                "height": Int32(size.height), "frame_rate": Double(rate > 0 ? rate : 30)]
    }

    static func composition(_ project: EditorProject) async throws -> AVMutableComposition {
        guard !project.track.clips.isEmpty else { throw EditorFailure(message: "Add a clip first") }
        let composition = AVMutableComposition()
        guard let videoOutput = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audioOutput = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw EditorFailure(message: "Cannot allocate composition tracks")
        }
        var referenceSize: CGSize?
        var referenceTransform: CGAffineTransform?
        for clip in project.track.clips.sorted(by: { $0.position.seconds < $1.position.seconds }) {
            guard let media = project.media.first(where: { $0.id == clip.media_id }) else { throw EditorFailure(message: "Missing media") }
            let asset = AVURLAsset(url: URL(fileURLWithPath: media.path))
            guard let video = try await asset.loadTracks(withMediaType: .video).first else { throw EditorFailure(message: "Missing video track: \(media.path)") }
            let size = try await video.load(.naturalSize)
            let transform = try await video.load(.preferredTransform)
            if let referenceSize, let referenceTransform,
               size != referenceSize || transform != referenceTransform {
                throw EditorFailure(message: "This milestone requires matching clip dimensions and orientation")
            }
            referenceSize = size
            referenceTransform = transform
            videoOutput.preferredTransform = transform
            let range = CMTimeRange(start: clip.source_start.cmTime, duration: clip.duration.cmTime)
            try videoOutput.insertTimeRange(range, of: video, at: clip.position.cmTime)
            if let audio = try await asset.loadTracks(withMediaType: .audio).first {
                let available = try await audio.load(.timeRange)
                let intersection = CMTimeRangeGetIntersection(range, otherRange: available)
                if intersection.duration > .zero {
                    let offset = CMTimeSubtract(intersection.start, range.start)
                    try audioOutput.insertTimeRange(intersection, of: audio, at: CMTimeAdd(clip.position.cmTime, offset))
                }
            }
        }
        return composition
    }

    static func export(_ project: EditorProject, to destination: URL) async throws {
        let composition = try await composition(project)
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality),
              session.supportedFileTypes.contains(.mp4) else { throw EditorFailure(message: "MP4 export is unavailable") }
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".export-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: temporary) }
        session.outputURL = temporary
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        await withCheckedContinuation { continuation in
            session.exportAsynchronously { continuation.resume() }
        }
        guard session.status == .completed else { throw session.error ?? EditorFailure(message: "Export failed") }
        let exported = AVURLAsset(url: temporary)
        guard let track = try await exported.loadTracks(withMediaType: .video).first else { throw EditorFailure(message: "Export has no video") }
        let formats = try await track.load(.formatDescriptions)
        guard formats.contains(where: { CMFormatDescriptionGetMediaSubType($0) == kCMVideoCodecType_H264 }) else {
            throw EditorFailure(message: "Export did not produce H.264")
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } else { try FileManager.default.moveItem(at: temporary, to: destination) }
    }
}
