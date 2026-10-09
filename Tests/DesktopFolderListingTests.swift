import XCTest
@testable import QuickDesktop

final class DesktopFolderListingTests: XCTestCase {
    func testTrackedFolderFixtureIsNewestFirstWithRealFileURLs() throws {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let dir = try TrackedFolderFixture.make(files: [
            ("oldest.txt", Data("old".utf8), t0),
            ("middle.pdf", Data("mid".utf8), t0.addingTimeInterval(60)),
            ("Screenshot 2026-09-14 at 10.41.00.png", Data("shot".utf8), t0.addingTimeInterval(120)),
        ])
        defer { try? FileManager.default.removeItem(at: dir) }

        // Hidden files must not appear in the grab list.
        try Data("junk".utf8).write(to: dir.appendingPathComponent(".DS_Store"))
        try Data("tmp".utf8).write(to: dir.appendingPathComponent(".hidden-shot.png"))

        let result = DesktopFolderListing.load(at: dir)
        let files = try result.get()

        XCTAssertEqual(files.map(\.name), [
            "Screenshot 2026-09-14 at 10.41.00.png",
            "middle.pdf",
            "oldest.txt",
        ])

        XCTAssertTrue(files.allSatisfy { $0.url.isFileURL })
        XCTAssertEqual(
            files[0].url.standardizedFileURL.path,
            dir.appendingPathComponent("Screenshot 2026-09-14 at 10.41.00.png").standardizedFileURL.path
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: files[0].url.path))
        XCTAssertFalse(files.contains { $0.name.hasPrefix(".") })
    }

    func testSortNewestFirstTieBreaksByName() {
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        let files = [
            DesktopFile(url: URL(fileURLWithPath: "/tmp/b.png"), name: "b.png", modifiedAt: t, size: 1, isDirectory: false),
            DesktopFile(url: URL(fileURLWithPath: "/tmp/a.png"), name: "a.png", modifiedAt: t, size: 1, isDirectory: false),
            DesktopFile(url: URL(fileURLWithPath: "/tmp/c.png"), name: "c.png", modifiedAt: t.addingTimeInterval(10), size: 1, isDirectory: false),
        ]
        XCTAssertEqual(DesktopFolderListing.sortedNewestFirst(files).map(\.name), ["c.png", "a.png", "b.png"])
    }

    func testDotfilesAreNotListed() {
        XCTAssertFalse(DesktopFolderListing.isListedFileName(".DS_Store"))
        XCTAssertFalse(DesktopFolderListing.isListedFileName(".hidden"))
        XCTAssertFalse(DesktopFolderListing.isListedFileName("Icon\r"))
        XCTAssertTrue(DesktopFolderListing.isListedFileName("Screenshot 1.png"))
    }

    func testMissingFolderIsAFailureNotAnEmptyList() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("quick-desktop-missing-\(UUID().uuidString)")
        let result = DesktopFolderListing.load(at: missing)
        switch result {
        case .success:
            XCTFail("missing folder should not scan as an empty success")
        case .failure:
            break
        }
    }
}
