import AppKit
import Carbon.HIToolbox
import Combine

@MainActor
final class SiteStore: ObservableObject {
    @Published private(set) var sites: [Site] = [] {
        didSet {
            save()
            registerHotKeys()
        }
    }
    @Published private(set) var recordingSiteID: UUID?
    @Published private(set) var unavailableShortcutIDs: Set<UUID> = []

    private static let chromeBundleID = "com.google.Chrome"

    private lazy var hotKeys = HotKeyCenter { [weak self] siteID in
        Task { @MainActor in self?.openSite(siteID) }
    }

    init() {
        sites = Self.load()
        registerHotKeys()
    }

    @discardableResult
    func add(address: String, title: String) -> Bool {
        guard let url = Site.normalizedURL(from: address) else { return false }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        sites.append(Site(title: trimmedTitle.isEmpty ? (url.host ?? url.absoluteString) : trimmedTitle, url: url))
        return true
    }

    func delete(_ id: UUID) {
        if recordingSiteID == id { recordingSiteID = nil }
        sites.removeAll { $0.id == id }
    }

    // MARK: - Shortcuts

    func beginRecording(_ id: UUID) {
        recordingSiteID = id
        registerHotKeys()
    }

    func cancelRecording() {
        guard recordingSiteID != nil else { return }
        recordingSiteID = nil
        registerHotKeys()
    }

    func clearShortcut(_ id: UUID) {
        guard let index = sites.firstIndex(where: { $0.id == id }) else { return }
        sites[index].shortcut = nil
    }

    func handleKeyDown(_ event: NSEvent) -> Bool {
        guard let id = recordingSiteID else { return false }
        let isDelete = [kVK_Delete, kVK_ForwardDelete].contains(Int(event.keyCode))
        switch Int(event.keyCode) {
        case kVK_Escape:
            cancelRecording()
        case _ where isDelete && event.modifierFlags.isDisjoint(with: [.command, .control, .option]):
            recordingSiteID = nil
            clearShortcut(id)
        default:
            guard let shortcut = Shortcut(event: event) else {
                NSSound.beep()
                return true
            }
            assign(shortcut, to: id)
        }
        return true
    }

    private func assign(_ shortcut: Shortcut, to id: UUID) {
        recordingSiteID = nil
        var updated = sites
        for index in updated.indices where updated[index].shortcut == shortcut {
            updated[index].shortcut = nil
        }
        guard let index = updated.firstIndex(where: { $0.id == id }) else { return }
        updated[index].shortcut = shortcut
        sites = updated
    }

    private func registerHotKeys() {
        guard recordingSiteID == nil else {
            hotKeys.unregisterAll()
            return
        }
        let entries = sites.compactMap { site in site.shortcut.map { (siteID: site.id, shortcut: $0) } }
        unavailableShortcutIDs = hotKeys.register(entries)
    }

    private func openSite(_ id: UUID) {
        guard let site = sites.first(where: { $0.id == id }) else { return }
        open(site)
    }

    func open(_ site: Site) {
        if focusExistingChromeTab(for: site) { return }
        guard let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.chromeBundleID) else {
            NSWorkspace.shared.open(site.url)
            return
        }
        NSWorkspace.shared.open([site.url], withApplicationAt: chrome, configuration: NSWorkspace.OpenConfiguration())
    }

    private func focusExistingChromeTab(for site: Site) -> Bool {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: Self.chromeBundleID).isEmpty,
              let windows = runChromeScript("get URL of every tab of every window") else { return false }

        for windowIndex in 1...max(1, windows.numberOfItems) {
            guard let tabs = windows.atIndex(windowIndex) else { continue }
            for tabIndex in 1...max(1, tabs.numberOfItems) {
                guard let tabURL = tabs.atIndex(tabIndex)?.stringValue,
                      site.matches(tabURL: tabURL) else { continue }
                return runChromeScript("""
                    set active tab index of window \(windowIndex) to \(tabIndex)
                    set index of window \(windowIndex) to 1
                    activate
                    """) != nil
            }
        }
        return false
    }

    private func runChromeScript(_ body: String) -> NSAppleEventDescriptor? {
        let source = "tell application id \"\(Self.chromeBundleID)\"\n\(body)\nend tell"
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil ? result : nil
    }

    private static var storeURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSString("~/Library/Application Support").expandingTildeInPath)
        let directory = base.appendingPathComponent("quick-desktop", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("sites.json")
    }

    private static func load() -> [Site] {
        guard let data = try? Data(contentsOf: storeURL) else { return [] }
        return (try? JSONDecoder().decode([Site].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(sites) else { return }
        try? data.write(to: Self.storeURL, options: .atomic)
    }
}
