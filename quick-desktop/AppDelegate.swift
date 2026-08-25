import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController()
        // Sparkle's updater is otherwise created the first time the right-click
        // menu asks whether it can check for updates, stalling that menu.
        Task { @MainActor in _ = UpdaterController.shared }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // The notes save is debounced; on quit there is no later chance to run it.
        statusBarController?.flushPendingEdits()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
