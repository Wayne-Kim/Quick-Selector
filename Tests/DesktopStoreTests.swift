import XCTest
@testable import QuickDesktop

@MainActor
final class DesktopStoreTests: XCTestCase {
    func testStoreListsTrackedFolderNewestFirst() async throws {
        let t0 = Date(timeIntervalSince1970: 1_700_000_200)
        let dir = try TrackedFolderFixture.make(files: [
            ("old-receipt.pdf", Data("a".utf8), t0),
            ("notes.txt", Data("b".utf8), t0.addingTimeInterval(30)),
            ("Screenshot 2026-09-14.png", Data("c".utf8), t0.addingTimeInterval(90)),
        ])
        defer { try? FileManager.default.removeItem(at: dir) }

        let (store, defaults, suite) = makeStore(folder: dir)
        defer { defaults.removePersistentDomain(forName: suite) }

        if store.scanStatus == .pending {
            XCTAssertFalse(store.showsEmptyFolder, "empty-state must not lie while the scan is still pending")
        }

        await store.awaitIdle()

        XCTAssertEqual(store.scanStatus, .ready)
        XCTAssertEqual(store.files.map(\.name), [
            "Screenshot 2026-09-14.png",
            "notes.txt",
            "old-receipt.pdf",
        ])
        XCTAssertTrue(store.files[0].url.isFileURL)
        XCTAssertEqual(
            store.files[0].url.standardizedFileURL.path,
            dir.appendingPathComponent("Screenshot 2026-09-14.png").standardizedFileURL.path
        )
        XCTAssertFalse(store.showsEmptyFolder)
        XCTAssertFalse(store.showsLoadingPlaceholder)
        XCTAssertFalse(store.showsPermissionDenied)
        XCTAssertFalse(store.showsReadFailure)
    }

    func testReadyEmptyFolderIsDistinctFromPendingAndFromReadFailure() async throws {
        let empty = try TrackedFolderFixture.make(files: [])
        defer { try? FileManager.default.removeItem(at: empty) }

        let (emptyStore, emptyDefaults, emptySuite) = makeStore(folder: empty)
        defer { emptyDefaults.removePersistentDomain(forName: emptySuite) }
        await emptyStore.awaitIdle()
        XCTAssertTrue(emptyStore.showsEmptyFolder)
        XCTAssertFalse(emptyStore.showsLoadingPlaceholder)
        XCTAssertFalse(emptyStore.showsReadFailure)

        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("quick-desktop-missing-\(UUID().uuidString)")
        let (failedStore, failedDefaults, failedSuite) = makeStore(folder: missing)
        defer { failedDefaults.removePersistentDomain(forName: failedSuite) }
        await failedStore.awaitIdle()
        XCTAssertTrue(failedStore.showsReadFailure)
        XCTAssertFalse(failedStore.showsEmptyFolder)
        XCTAssertTrue(failedStore.files.isEmpty)
    }

    func testSwitchingFolderRescansTheNewTrackedDirectory() async throws {
        let t0 = Date(timeIntervalSince1970: 1_700_000_300)
        let desktop = try TrackedFolderFixture.make(files: [
            ("Screenshot.png", Data("s".utf8), t0.addingTimeInterval(10)),
        ])
        let downloads = try TrackedFolderFixture.make(files: [
            ("older.txt", Data("o".utf8), t0),
            ("latest.zip", Data("z".utf8), t0.addingTimeInterval(40)),
        ])
        defer {
            try? FileManager.default.removeItem(at: desktop)
            try? FileManager.default.removeItem(at: downloads)
        }

        let (store, defaults, suite) = makeStore(folder: desktop)
        defer { defaults.removePersistentDomain(forName: suite) }
        await store.awaitIdle()
        XCTAssertEqual(store.files.map(\.name), ["Screenshot.png"])

        store.setFolder(downloads)
        XCTAssertFalse(store.showsEmptyFolder, "must not claim the new folder is empty before it has been scanned")
        await store.awaitIdle()
        XCTAssertEqual(store.files.map(\.name), ["latest.zip", "older.txt"])
        XCTAssertEqual(store.folderURL.standardizedFileURL, downloads.standardizedFileURL)
    }

    func testRefreshPicksUpANewFileAsNewest() async throws {
        let t0 = Date(timeIntervalSince1970: 1_700_000_400)
        let dir = try TrackedFolderFixture.make(files: [
            ("old.txt", Data("o".utf8), t0),
        ])
        defer { try? FileManager.default.removeItem(at: dir) }

        let (store, defaults, suite) = makeStore(folder: dir)
        defer { defaults.removePersistentDomain(forName: suite) }
        await store.awaitIdle()
        XCTAssertEqual(store.files.map(\.name), ["old.txt"])

        let incoming = dir.appendingPathComponent("Screenshot 2026-09-14.png")
        try Data("shot".utf8).write(to: incoming, options: .atomic)
        try FileManager.default.setAttributes(
            [.modificationDate: t0.addingTimeInterval(120)],
            ofItemAtPath: incoming.path
        )
        store.refresh()
        await store.awaitIdle()
        XCTAssertEqual(store.files.map(\.name), ["Screenshot 2026-09-14.png", "old.txt"])
        XCTAssertTrue(store.files[0].url.isFileURL)
        XCTAssertEqual(store.files[0].url.standardizedFileURL.path, incoming.standardizedFileURL.path)
    }

    private func makeStore(folder: URL) -> (DesktopStore, UserDefaults, String) {
        let suite = "quick-desktop.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = DesktopStore(folderURL: folder, defaults: defaults)
        return (store, defaults, suite)
    }
}
