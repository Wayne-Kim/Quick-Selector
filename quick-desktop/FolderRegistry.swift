import AppKit
import Combine
import Foundation

@MainActor
final class FolderRegistry: ObservableObject {
    @Published private(set) var folders: [TrackedFolder] = []

    private static let defaultsKey = "trackedFolders"
    private static let legacyDefaultsKey = "trackedFolderPath"

    static var desktopURL: URL {
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSString("~/Desktop").expandingTildeInPath)
    }

    init() {
        folders = Self.loadPersisted()
    }

    var urls: [URL] { folders.map(\.url) }

    var isDesktopOnly: Bool {
        folders.count == 1 && folders[0].url.standardizedFileURL == Self.desktopURL.standardizedFileURL
    }

    func folder(atPath path: String) -> TrackedFolder? {
        folders.first { $0.path == path }
    }

    /// Presents a directory picker and adds everything the user confirms.
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.prompt = "Track"
        panel.message = "Choose folders for Quick Desktop to track."
        panel.directoryURL = folders.last?.url ?? Self.desktopURL
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        add(panel.urls)
    }

    func add(_ urls: [URL]) {
        var next = folders
        for url in urls {
            let path = url.standardizedFileURL.path
            guard !next.contains(where: { $0.path == path }) else { continue }
            next.append(TrackedFolder(path: path, colorIndex: Self.freeColorIndex(in: next)))
        }
        guard next != folders else { return }
        folders = next
        persist()
    }

    func remove(_ folder: TrackedFolder) {
        guard let index = folders.firstIndex(of: folder) else { return }
        folders.remove(at: index)
        persist()
    }

    func resetToDesktopOnly() {
        let desktop = TrackedFolder(path: Self.desktopURL.standardizedFileURL.path, colorIndex: 0)
        guard folders != [desktop] else { return }
        folders = [desktop]
        persist()
    }

    private static func freeColorIndex(in folders: [TrackedFolder]) -> Int {
        let used = Set(folders.map(\.colorIndex))
        return (0..<TrackedFolder.palette.count).first { !used.contains($0) } ?? folders.count
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(folders) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    /// Reads the stored list, migrating the single-folder key written by
    /// earlier versions. A folder that is currently unreachable stays in the
    /// list so an unplugged volume doesn't silently drop out of it.
    private static func loadPersisted() -> [TrackedFolder] {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: defaultsKey),
           let stored = try? JSONDecoder().decode([TrackedFolder].self, from: data) {
            return stored
        }
        if let legacyPath = defaults.string(forKey: legacyDefaultsKey) {
            defaults.removeObject(forKey: legacyDefaultsKey)
            let migrated = [TrackedFolder(path: legacyPath, colorIndex: 0)]
            if let data = try? JSONEncoder().encode(migrated) {
                defaults.set(data, forKey: defaultsKey)
            }
            return migrated
        }
        return [TrackedFolder(path: desktopURL.standardizedFileURL.path, colorIndex: 0)]
    }
}
