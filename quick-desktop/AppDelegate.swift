import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController()
        // Sparkle's updater is otherwise created the first time the right-click
        // menu asks whether it can check for updates, stalling that menu.
        Task { @MainActor in _ = UpdaterController.shared }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
