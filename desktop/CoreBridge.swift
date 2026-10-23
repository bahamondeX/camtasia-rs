import Foundation
import CoreMedia

struct EditorTime: Codable {
    let value: Int64
    let timescale: Int32
    var seconds: Double { Double(value) / Double(timescale) }
    var cmTime: CMTime { CMTime(value: value, timescale: timescale) }
    var json: [String: Any] { ["value": value, "timescale": timescale] }
    init(_ time: CMTime) { value = time.value; timescale = time.timescale }
    init(seconds: Double) { self.init(CMTime(seconds: seconds, preferredTimescale: 60000)) }
}
struct EditorMedia: Codable, Identifiable {
    let id: UInt64
    let path: String
    let duration: EditorTime
    let width: Int32
    let height: Int32
    let frame_rate: Double
}
struct EditorClip: Codable, Identifiable {
    let id: UInt64
    let media_id: UInt64
    let position: EditorTime
    let source_start: EditorTime
    let duration: EditorTime
}
struct EditorTrack: Codable { let id: UInt64; let clips: [EditorClip] }
struct EditorProject: Codable {
    let version: UInt32
    let next_id: UInt64
    let media: [EditorMedia]
    let track: EditorTrack
}
struct EditorFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
final class CoreBridge {
    private let handle: UnsafeMutableRawPointer
    init() { handle = editor_create()! }
    deinit { editor_destroy(handle) }
    @discardableResult
    func execute(_ command: [String: Any]) throws -> EditorProject {
        let request = try JSONSerialization.data(withJSONObject: command)
        let text = String(decoding: request, as: UTF8.self)
        guard let response = text.withCString({ editor_execute(handle, $0) }) else {
            throw EditorFailure(message: "Core returned no response")
        }
        defer { editor_free(response) }
        let data = Data(String(cString: response).utf8)
        struct Response: Decodable { let project: EditorProject?; let error: String? }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let project = decoded.project else { throw EditorFailure(message: decoded.error ?? "Invalid core response") }
        return project
    }
}
