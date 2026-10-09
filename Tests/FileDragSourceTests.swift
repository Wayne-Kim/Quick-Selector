import UniformTypeIdentifiers
import XCTest
@testable import QuickDesktop

final class FileDragSourceTests: XCTestCase {
    func testDragProviderLoadsTheRealFileURLNotAFilenameString() async throws {
        let t0 = Date(timeIntervalSince1970: 1_700_000_100)
        let dir = try TrackedFolderFixture.make(files: [
            ("Screenshot 2026-09-14.png", Data("png-bytes".utf8), t0),
        ])
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = dir.appendingPathComponent("Screenshot 2026-09-14.png").standardizedFileURL
        let provider = FileDragSource.itemProvider(for: fileURL)

        XCTAssertFalse(provider.registeredTypeIdentifiers.isEmpty, "empty NSItemProvider cannot drop a file")
        XCTAssertNotEqual(provider.registeredTypeIdentifiers, ["public.utf8-plain-text"])
        XCTAssertTrue(
            provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
                || provider.hasItemConformingToTypeIdentifier(UTType.data.identifier)
                || provider.registeredTypeIdentifiers.contains(where: { UTType($0)?.conforms(to: .item) == true }),
            "provider types were \(provider.registeredTypeIdentifiers)"
        )

        let loaded = try await FileDragSource.loadFileURL(from: provider)
        XCTAssertTrue(loaded.isFileURL, "drop target received \(loaded) which is not a file URL")
        XCTAssertNotEqual(loaded.absoluteString, fileURL.lastPathComponent)
        XCTAssertEqual(loaded.lastPathComponent, fileURL.lastPathComponent)
        XCTAssertTrue(FileManager.default.fileExists(atPath: loaded.path))
        XCTAssertEqual(loaded.standardizedFileURL.path, fileURL.path)
    }
}
