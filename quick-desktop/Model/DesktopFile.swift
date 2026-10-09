import Foundation

struct DesktopFile: Identifiable, Hashable, Sendable {
    let url: URL
    let name: String
    let modifiedAt: Date
    let size: Int64
    let isDirectory: Bool

    var id: URL { url }
}
