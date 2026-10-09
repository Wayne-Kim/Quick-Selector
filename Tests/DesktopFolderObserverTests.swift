import XCTest
@testable import QuickDesktop

final class DesktopFolderObserverTests: XCTestCase {
    func testNewFileInTrackedFolderFiresChange() throws {
        let dir = try TrackedFolderFixture.make(files: [])
        defer { try? FileManager.default.removeItem(at: dir) }

        let fired = expectation(description: "observer saw a new file")
        fired.assertForOverFulfill = false
        let observer = DesktopFolderObserver(url: dir, debounceMilliseconds: 20) {
            fired.fulfill()
        }
        observer.start()
        defer { observer.stop() }

        let incoming = dir.appendingPathComponent("Screenshot 2026-09-14.png")
        try Data("shot".utf8).write(to: incoming, options: .atomic)

        wait(for: [fired], timeout: 2.0)
    }
}
