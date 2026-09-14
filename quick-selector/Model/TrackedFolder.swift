import Foundation
import SwiftUI

struct TrackedFolder: Identifiable, Hashable, Codable {
    let path: String
    let colorIndex: Int

    var id: String { path }

    var url: URL { URL(fileURLWithPath: path) }

    var name: String {
        let display = FileManager.default.displayName(atPath: path)
        return display.isEmpty ? url.lastPathComponent : display
    }

    var color: Color { Self.palette[colorIndex % Self.palette.count] }

    static let palette: [Color] = [.blue, .orange, .green, .purple, .pink, .teal, .indigo, .brown]
}
