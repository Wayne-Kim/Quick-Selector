import AppKit

@MainActor
final class StatusBarController {
    private let statusItem: NSStatusItem
    private let panelController: PanelController

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        panelController = PanelController()

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "square.stack.3d.up", accessibilityDescription: "Quick Desktop")
            image?.isTemplate = true
            button.image = image
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        let isRight = NSApp.currentEvent?.type == .rightMouseUp
        if isRight {
            showMenu()
        } else {
            panelController.toggle(relativeTo: statusItem.button)
        }
    }

    private func showMenu() {
        let menu = NSMenu()

        let openDesktop = NSMenuItem(title: "Open Desktop in Finder", action: #selector(openDesktopInFinder), keyEquivalent: "")
        openDesktop.target = self
        menu.addItem(openDesktop)

        menu.addItem(.separator())

        let launchAtLogin = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLogin.target = self
        launchAtLogin.state = LoginItemController.isEnabled ? .on : .off
        menu.addItem(launchAtLogin)

        menu.addItem(.separator())

        let checkUpdate = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        checkUpdate.target = self
        checkUpdate.isEnabled = UpdaterController.shared.canCheckForUpdates
        menu.addItem(checkUpdate)

        menu.addItem(.separator())

        let about = NSMenuItem(title: aboutTitle, action: nil, keyEquivalent: "")
        about.isEnabled = false
        menu.addItem(about)

        let quit = NSMenuItem(title: "Quit Quick Desktop", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private var aboutTitle: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Quick Desktop \(version) (\(build))"
    }

    @objc private func openDesktopInFinder() {
        let url = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSString("~/Desktop").expandingTildeInPath)
        NSWorkspace.shared.open(url)
    }

    @objc private func toggleLaunchAtLogin() {
        LoginItemController.toggle()
    }

    @objc private func checkForUpdates() {
        UpdaterController.shared.checkForUpdates()
    }
}
