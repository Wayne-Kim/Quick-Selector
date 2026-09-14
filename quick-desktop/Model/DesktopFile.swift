import Foundation

struct DesktopFile: Identifiable, Hashable {
    let url: URL
    let name: String
    let modifiedAt: Date
    let size: Int64
    let isDirectory: Bool
    let folderPath: String

    var id: URL { url }

    var kind: String { isDirectory ? "" : url.pathExtension.lowercased() }
}
