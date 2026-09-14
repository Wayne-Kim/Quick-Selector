import AppKit

@MainActor
final class StatusBarController {
    private let statusItem: NSStatusItem
    private let panelController: PanelController

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        panelController = PanelController()

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "square.stack.3d.up", accessibilityDescription: "Quick Selector")
            image?.isTemplate = true
            button.image = image
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    /// Writes out an in-progress note edit. Called on quit.
    func flushPendingEdits() {
        panelController.flushPendingEdits()
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
        menu.autoenablesItems = false

        addOpenInFinderItems(to: menu)

        let addFolder = NSMenuItem(title: "Add Folder to Track...", action: #selector(addFolder), keyEquivalent: "")
        addFolder.target = self
        menu.addItem(addFolder)

        let resetFolder = NSMenuItem(title: "Reset to Desktop Only", action: #selector(resetFolder), keyEquivalent: "")
        resetFolder.target = self
        resetFolder.isEnabled = !panelController.registry.isDesktopOnly
        menu.addItem(resetFolder)

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

        let quit = NSMenuItem(title: "Quit Quick Selector", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private var aboutTitle: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Quick Selector \(version) (\(build))"
    }

    /// Lists the tracked folders directly when there is only one, and behind a
    /// submenu when there are several.
    private func addOpenInFinderItems(to menu: NSMenu) {
        let folders = panelController.registry.folders
        guard !folders.isEmpty else { return }
        if folders.count == 1, let folder = folders.first {
            menu.addItem(openItem(for: folder, title: "Open \(folder.name) in Finder"))
            return
        }
        let parent = NSMenuItem(title: "Open in Finder", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for folder in folders {
            submenu.addItem(openItem(for: folder, title: folder.name))
        }
        parent.submenu = submenu
        menu.addItem(parent)
    }

    private func openItem(for folder: TrackedFolder, title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(openFolderInFinder(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = folder.path
        return item
    }

    @objc private func openFolderInFinder(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    @objc private func addFolder() {
        panelController.registry.chooseFolder()
    }

    @objc private func resetFolder() {
        panelController.registry.resetToDesktopOnly()
    }

    @objc private func toggleLaunchAtLogin() {
        LoginItemController.toggle()
    }

    @objc private func checkForUpdates() {
        UpdaterController.shared.checkForUpdates()
    }
}
