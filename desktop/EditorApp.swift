import SwiftUI
import AppKit
import AVKit
import UniformTypeIdentifiers

@MainActor
final class EditorModel: ObservableObject {
    let core = CoreBridge()
    @Published var project: EditorProject
    @Published var player = AVPlayer()
    @Published var selectedMedia: UInt64?
    @Published var selectedClip: UInt64?
    @Published var sourceIn = 0.0
    @Published var sourceOut = 0.0
    @Published var position = 0.0
    @Published var message = "Import an MP4 to begin"
    @Published var busy = false
    init() { project = try! core.execute(["command": "project.create"]) }
    func run(_ operation: @escaping () async throws -> Void) {
        busy = true
        Task {
            defer { busy = false }
            do { try await operation() } catch { message = error.localizedDescription }
        }
    }
    func edit(_ command: [String: Any]) throws { project = try core.execute(command) }
    func importVideo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mpeg4Movie, .movie]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        run {
            try self.edit(await MediaEngine.importCommand(url))
            self.selectedMedia = self.project.media.last?.id
            self.previewMedia()
            self.message = "Imported \(url.lastPathComponent). Add it to the timeline."
        }
    }
    func previewMedia() {
        guard let media = project.media.first(where: { $0.id == selectedMedia }) else { return }
        player.replaceCurrentItem(with: AVPlayerItem(url: URL(fileURLWithPath: media.path)))
    }
    func previewTimeline() async throws {
        player.replaceCurrentItem(with: AVPlayerItem(asset: try await MediaEngine.composition(project)))
        message = "Timeline preview ready"
    }
    func addClip() {
        guard let mediaID = selectedMedia else { return }
        run {
            let end = self.project.track.clips.map { CMTimeAdd($0.position.cmTime, $0.duration.cmTime) }.max() ?? .zero
            try self.edit(["command": "timeline.add_clip", "media_id": mediaID, "position": EditorTime(end).json])
            if let clip = self.project.track.clips.last { self.select(clip) }
            try await self.previewTimeline()
        }
    }
    func select(_ clip: EditorClip) {
        selectedClip = clip.id
        sourceIn = clip.source_start.seconds
        sourceOut = sourceIn + clip.duration.seconds
        position = clip.position.seconds
    }
    func trim() {
        guard let clipID = selectedClip else { return }
        run {
            guard self.sourceIn.isFinite, self.sourceOut.isFinite, self.sourceOut > self.sourceIn else { throw EditorFailure(message: "Out must be greater than In") }
            try self.edit(["command": "timeline.trim_clip", "clip_id": clipID,
                           "source_start": EditorTime(seconds: self.sourceIn).json,
                           "duration": EditorTime(seconds: self.sourceOut - self.sourceIn).json])
            try await self.previewTimeline()
        }
    }
    func move() {
        guard let clipID = selectedClip else { return }
        run {
            guard self.position.isFinite else { throw EditorFailure(message: "Invalid position") }
            try self.edit(["command": "timeline.move_clip", "clip_id": clipID, "position": EditorTime(seconds: self.position).json])
            try await self.previewTimeline()
        }
    }
    func remove() {
        guard let clipID = selectedClip else { return }
        run {
            try self.edit(["command": "timeline.remove_clip", "clip_id": clipID])
            self.selectedClip = nil
            self.player.replaceCurrentItem(with: nil)
            self.message = "Clip removed"
        }
    }
    func saveProject() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "project.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        run { try self.edit(["command": "project.save", "path": url.path]); self.message = "Project saved" }
    }
    func openProject() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        run {
            try self.edit(["command": "project.open", "path": url.path])
            self.selectedMedia = self.project.media.first?.id
            self.selectedClip = nil
            if !self.project.track.clips.isEmpty { try await self.previewTimeline() }
            else { self.previewMedia() }
        }
    }
    func exportVideo() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.mpeg4Movie]; panel.nameFieldStringValue = "edited.mp4"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        run {
            self.message = "Exporting…"
            try await MediaEngine.export(self.project, to: url)
            self.player.replaceCurrentItem(with: AVPlayerItem(url: url))
            self.message = "Exported \(url.lastPathComponent). Press Play to review."
        }
    }
}

struct EditorView: View {
    @StateObject private var model = EditorModel()
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("Import Video…", action: model.importVideo).accessibilityIdentifier("importVideo")
                Button("Open Project…", action: model.openProject)
                Button("Save Project…", action: model.saveProject)
                Spacer()
                Button("Export MP4…", action: model.exportVideo).disabled(model.project.track.clips.isEmpty)
            }
            HStack(alignment: .top) {
                VStack(alignment: .leading) {
                    Text("Media").font(.headline)
                    List(model.project.media, selection: $model.selectedMedia) { media in
                        VStack(alignment: .leading) {
                            Text(URL(fileURLWithPath: media.path).lastPathComponent)
                            Text("\(media.width) × \(media.height) · \(media.duration.seconds, specifier: "%.2f") s").font(.caption)
                        }.tag(media.id)
                    }.frame(width: 230)
                    Button("Preview Source", action: model.previewMedia).disabled(model.selectedMedia == nil)
                    Button("Add to Timeline", action: model.addClip).disabled(model.selectedMedia == nil)
                }
                VideoPlayer(player: model.player).frame(minWidth: 480, minHeight: 300)
            }
            HStack {
                Text("Timeline · Track 1").font(.headline)
                Button("Preview Timeline") { model.run { try await model.previewTimeline() } }.disabled(model.project.track.clips.isEmpty)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(model.project.track.clips.sorted(by: { $0.position.seconds < $1.position.seconds })) { clip in
                        Button { model.select(clip) } label: {
                            VStack(alignment: .leading) {
                                Text(model.project.media.first(where: { $0.id == clip.media_id }).map { URL(fileURLWithPath: $0.path).lastPathComponent } ?? "Missing media")
                                Text("At \(clip.position.seconds, specifier: "%.2f") s · \(clip.duration.seconds, specifier: "%.2f") s")
                            }.padding(10).frame(minWidth: 150)
                        }.tint(model.selectedClip == clip.id ? .accentColor : .gray)
                    }
                }.padding(4)
            }.frame(height: 80)
            HStack {
                Text("Source In (s)")
                TextField("In", value: $model.sourceIn, format: .number).frame(width: 85)
                Text("Source Out (s)")
                TextField("Out", value: $model.sourceOut, format: .number).frame(width: 85)
                Button("Apply Trim", action: model.trim)
                Text("Position (s)")
                TextField("Position", value: $model.position, format: .number).frame(width: 85)
                Button("Move", action: model.move)
                Button("Delete Clip", action: model.remove)
            }.disabled(model.selectedClip == nil)
            HStack { if model.busy { ProgressView().controlSize(.small) }; Text(model.message).textSelection(.enabled) }
        }.padding(16).frame(minWidth: 1000, minHeight: 650).disabled(model.busy)
    }
}

@main
struct CamtasiaRSApp: App {
    var body: some Scene { WindowGroup("Camtasia RS") { EditorView() } }
}
