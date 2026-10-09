import Foundation

/// A disposable directory that stands in for Desktop in tests.
enum TrackedFolderFixture {
    static func make(files: [(name: String, contents: Data, modifiedAt: Date)]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quick-desktop-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for file in files {
            let url = root.appendingPathComponent(file.name)
            try file.contents.write(to: url, options: .atomic)
            try FileManager.default.setAttributes(
                [.modificationDate: file.modifiedAt],
                ofItemAtPath: url.path
            )
        }
        return root
    }
}
