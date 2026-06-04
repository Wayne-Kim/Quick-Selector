import Foundation
import Combine
import AppKit

@MainActor
final class DesktopStore: ObservableObject {
    @Published private(set) var files: [DesktopFile] = []
    @Published private(set) var hasAccess: Bool = true
    @Published private(set) var lastError: String?
    @Published private(set) var folderURL: URL

    private var observer: DesktopFolderObserver?

    private static let folderPathDefaultsKey = "trackedFolderPath"

    /// The folder tracked when the user hasn't chosen a custom one — the system Desktop.
    static var defaultFolderURL: URL {
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSString("~/Desktop").expandingTildeInPath)
    }

    init(folderURL: URL? = nil) {
        self.folderURL = folderURL ?? Self.loadPersistedFolder() ?? Self.defaultFolderURL
        startObserving()
    }

    /// `true` when tracking the system Desktop (i.e. no custom folder is set).
    var isTrackingDesktop: Bool {
        folderURL.standardizedFileURL == Self.defaultFolderURL.standardizedFileURL
    }

    /// Localized display name of the tracked folder, e.g. "Desktop", "Downloads".
    var folderName: String {
        let display = FileManager.default.displayName(atPath: folderURL.path)
        return display.isEmpty ? folderURL.lastPathComponent : display
    }

    // MARK: - Folder selection

    /// Presents a directory picker and, if the user confirms, switches to that folder.
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Track"
        panel.message = "Choose a folder for Quick Desktop to track."
        panel.directoryURL = folderURL
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setFolder(url)
    }

    /// Switches the tracked folder, persists the choice, and reloads.
    func setFolder(_ url: URL) {
        let normalized = url.standardizedFileURL
        guard normalized != folderURL.standardizedFileURL else { return }
        folderURL = normalized
        Self.persistFolder(normalized)
        startObserving()
        refresh()
    }

    /// Reverts to tracking the system Desktop.
    func resetToDesktop() {
        setFolder(Self.defaultFolderURL)
    }

    // MARK: - Persistence

    private static func loadPersistedFolder() -> URL? {
        guard let path = UserDefaults.standard.string(forKey: folderPathDefaultsKey) else { return nil }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    private static func persistFolder(_ url: URL) {
        let defaults = UserDefaults.standard
        if url.standardizedFileURL == defaultFolderURL.standardizedFileURL {
            defaults.removeObject(forKey: folderPathDefaultsKey)
        } else {
            defaults.set(url.path, forKey: folderPathDefaultsKey)
        }
    }

    // MARK: - Observing

    private func startObserving() {
        observer?.stop()
        let observer = DesktopFolderObserver(url: folderURL) { [weak self] in
            Task { @MainActor in
                self?.refresh()
            }
        }
        observer.start()
        self.observer = observer
    }

    func refresh() {
        let url = folderURL
        Task.detached { [weak self] in
            let result = Self.loadFiles(at: url)
            await MainActor.run {
                guard let self else { return }
                // Ignore results from a folder we've since switched away from.
                guard self.folderURL == url else { return }
                switch result {
                case .success(let files):
                    self.files = files
                    self.hasAccess = true
                    self.lastError = nil
                case .failure(let error):
                    self.files = []
                    let ns = error as NSError
                    if ns.domain == NSCocoaErrorDomain && (ns.code == NSFileReadNoPermissionError || ns.code == 257) {
                        self.hasAccess = false
                    }
                    self.lastError = ns.localizedDescription
                }
            }
        }
    }

    nonisolated private static func loadFiles(at url: URL) -> Result<[DesktopFile], Error> {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [
            .contentModificationDateKey,
            .fileSizeKey,
            .isDirectoryKey,
            .isHiddenKey,
            .nameKey,
        ]
        do {
            let urls = try fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
            var items: [DesktopFile] = []
            items.reserveCapacity(urls.count)
            for fileURL in urls {
                let name = fileURL.lastPathComponent
                if name.hasPrefix(".") { continue }
                if name == "Icon\r" { continue }
                let values = try? fileURL.resourceValues(forKeys: Set(keys))
                let mtime = values?.contentModificationDate ?? .distantPast
                let size = Int64(values?.fileSize ?? 0)
                let isDir = values?.isDirectory ?? false
                items.append(DesktopFile(
                    url: fileURL,
                    name: name,
                    modifiedAt: mtime,
                    size: size,
                    isDirectory: isDir
                ))
            }
            items.sort { $0.modifiedAt > $1.modifiedAt }
            return .success(items)
        } catch {
            return .failure(error)
        }
    }
}
