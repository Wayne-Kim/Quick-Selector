import XCTest
@testable import QuickDesktop

@MainActor
final class PanelStateTests: XCTestCase {
    func testOpeningThePanelLeavesNotesAndShowsFiles() {
        let state = PanelState()
        state.mode = .notes
        state.prepareForShow()
        XCTAssertEqual(state.mode, .files)
    }
}
