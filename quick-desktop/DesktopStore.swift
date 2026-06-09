import Foundation
import Combine
import AppKit

@MainActor
final class DesktopStore: ObservableObject {
    @Published private(set) var files: [DesktopFile] = []
    @Published private(set) var hasAccess: Bool = true
    @Published private(set) var lastError: String?
    @Published private(set) var folderURL: URL

    /// URLs of the currently selected files.
    @Published var selection: Set<URL> = []
    /// Absolute paths of files the user has starred ("to use this time").
    @Published private(set) var starredPaths: Set<String> = []
    /// The file currently being renamed inline, if any.
    @Published var renamingFileID: URL?
    /// Edited text bound to the inline rename field — the base name only.
    @Published var renameText: String = ""
    /// The renamed file's extension (without the dot); locked so it can't change.
    /// Empty for directories and extension-less files.
    @Published private(set) var renameExtension: String = ""

    /// Anchor of a shift/range selection; stays put while the focus end moves.
    private var selectionAnchor: URL?
    /// The moving end of the selection (the "cursor" for arrow navigation).
    private var selectionFocus: URL?

    /// Number of columns in the grid — must match `ContentView`'s layout so
    /// vertical arrow navigation lands on the right neighbour.
    let columnCount = 3

    /// Undo stack for reversible file operations (Trash / Rename).
    private let undoManager = UndoManager()

    private var observer: DesktopFolderObserver?

    private static let folderPathDefaultsKey = "trackedFolderPath"
    private static let starredDefaultsKey = "starredFilePaths"

    /// The folder tracked when the user hasn't chosen a custom one — the system Desktop.
    static var defaultFolderURL: URL {
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSString("~/Desktop").expandingTildeInPath)
    }

    init(folderURL: URL? = nil) {
        self.folderURL = folderURL ?? Self.loadPersistedFolder() ?? Self.defaultFolderURL
        self.starredPaths = Set(UserDefaults.standard.stringArray(forKey: Self.starredDefaultsKey) ?? [])
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
        clearSelection()
        undoManager.removeAllActions()
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

    // MARK: - Selection

    func isSelected(_ file: DesktopFile) -> Bool { selection.contains(file.url) }

    /// Selected files in current display order (so actions respect the on-screen order).
    var orderedSelectionURLs: [URL] { files.filter { selection.contains($0.url) }.map(\.url) }

    /// Replaces the selection with a single file and resets the range anchor.
    func select(_ file: DesktopFile) {
        commitRenameIfNeeded()
        selection = [file.url]
        selectionAnchor = file.url
        selectionFocus = file.url
    }

    /// Adds/removes a single file from the selection (⌘-click).
    func toggle(_ file: DesktopFile) {
        commitRenameIfNeeded()
        if selection.contains(file.url) {
            selection.remove(file.url)
        } else {
            selection.insert(file.url)
        }
        selectionAnchor = file.url
        selectionFocus = file.url
    }

    /// Selects the contiguous range, in display order, from the anchor to `file` (⇧-click).
    func extendSelection(to file: DesktopFile) {
        commitRenameIfNeeded()
        let anchorURL = selectionAnchor ?? selectionFocus ?? selection.first ?? file.url
        guard let a = files.firstIndex(where: { $0.url == anchorURL }),
              let b = files.firstIndex(where: { $0.url == file.url }) else {
            select(file)
            return
        }
        let range = a <= b ? a...b : b...a
        selection = Set(files[range].map(\.url))
        selectionAnchor = anchorURL
        selectionFocus = file.url
    }

    func selectAll() {
        commitRenameIfNeeded()
        selection = Set(files.map(\.url))
        selectionAnchor = files.first?.url
        selectionFocus = files.last?.url
    }

    func clearSelection() {
        commitRenameIfNeeded()
        selection = []
        selectionAnchor = nil
        selectionFocus = nil
    }

    enum MoveDirection { case left, right, up, down }

    /// Moves the selection cursor by one grid step; `extend` grows a range from the anchor.
    func moveSelection(_ direction: MoveDirection, extend: Bool) {
        guard !files.isEmpty else { return }
        let cursor = selectionFocus ?? selectionAnchor ?? selection.first
        guard let current = cursor, let idx = files.firstIndex(where: { $0.url == current }) else {
            select(files[0])
            return
        }
        let delta: Int
        switch direction {
        case .left: delta = -1
        case .right: delta = 1
        case .up: delta = -columnCount
        case .down: delta = columnCount
        }
        let target = idx + delta
        guard target >= 0, target < files.count else { return }
        if extend { extendSelection(to: files[target]) } else { select(files[target]) }
    }

    // MARK: - Actions on the selection

    func openSelection() {
        for url in orderedSelectionURLs { NSWorkspace.shared.open(url) }
    }

    func revealSelection() {
        let urls = orderedSelectionURLs
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func quickLookSelection() {
        let urls = orderedSelectionURLs
        guard !urls.isEmpty else { return }
        QuickLookController.shared.preview(urls)
    }

    func copySelection() {
        let urls = orderedSelectionURLs
        guard !urls.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(urls.map { $0 as NSURL })
    }

    func moveSelectionToTrash() {
        trash(orderedSelectionURLs)
    }

    /// Moves the given files to the Trash, registering a restore action for undo.
    func trash(_ urls: [URL]) {
        let moves = performTrash(urls)
        guard !moves.isEmpty else { return }
        registerRestoreUndo(for: moves)
        selectionAnchor = nil
        selectionFocus = nil
        refresh()
    }

    // MARK: - Stars

    func isStarred(_ file: DesktopFile) -> Bool { starredPaths.contains(file.url.path) }

    /// `true` when every selected file is already starred (drives the toggle's label).
    var allSelectionStarred: Bool {
        !selection.isEmpty && selection.allSatisfy { starredPaths.contains($0.path) }
    }

    func toggleStar(_ file: DesktopFile) {
        if starredPaths.contains(file.url.path) {
            starredPaths.remove(file.url.path)
        } else {
            starredPaths.insert(file.url.path)
        }
        persistStars()
    }

    func toggleStarForSelection() {
        let paths = selection.map(\.path)
        guard !paths.isEmpty else { return }
        let allStarred = paths.allSatisfy { starredPaths.contains($0) }
        for path in paths {
            if allStarred { starredPaths.remove(path) } else { starredPaths.insert(path) }
        }
        persistStars()
    }

    private func persistStars() {
        UserDefaults.standard.set(Array(starredPaths), forKey: Self.starredDefaultsKey)
    }

    // MARK: - Rename

    func beginRename(_ file: DesktopFile) {
        commitRenameIfNeeded()
        selection = [file.url]
        selectionAnchor = file.url
        selectionFocus = file.url
        // Lock the extension: only the base name is editable so the file type
        // can't be changed by accident. Directories have no protected extension.
        let ext = file.isDirectory ? "" : file.url.pathExtension
        renameExtension = ext
        renameText = ext.isEmpty ? file.name : file.url.deletingPathExtension().lastPathComponent
        renamingFileID = file.url
    }

    func beginRenameSelection() {
        guard selection.count == 1, let url = selection.first,
              let file = files.first(where: { $0.url == url }) else { return }
        beginRename(file)
    }

    func cancelRename() {
        renamingFileID = nil
    }

    private func commitRenameIfNeeded() {
        if renamingFileID != nil { commitRename() }
    }

    /// Applies the edited name to disk, re-attaching the locked extension.
    func commitRename() {
        guard let url = renamingFileID,
              let file = files.first(where: { $0.url == url }) else {
            renamingFileID = nil
            return
        }
        renamingFileID = nil
        let base = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty, !base.contains("/"), !base.contains(":") else { return }
        let newName = renameExtension.isEmpty ? base : "\(base).\(renameExtension)"
        guard newName != file.name else { return }
        let destination = file.url.deletingLastPathComponent().appendingPathComponent(newName)
        if FileManager.default.fileExists(atPath: destination.path) {
            lastError = "An item named “\(newName)” already exists."
            NSSound.beep()
            return
        }
        performRename(from: file.url, to: destination)
    }

    // MARK: - Undo / Redo

    var canUndo: Bool { undoManager.canUndo }
    var canRedo: Bool { undoManager.canRedo }

    func performUndo() {
        commitRenameIfNeeded()
        guard undoManager.canUndo else { NSSound.beep(); return }
        undoManager.undo()
    }

    func performRedo() {
        commitRenameIfNeeded()
        guard undoManager.canRedo else { NSSound.beep(); return }
        undoManager.redo()
    }

    // MARK: Trash primitives (shared by trash / undo / redo)

    /// Moves files to the Trash, capturing each item's resulting Trash URL so it
    /// can be restored. Returns the (original, trashed) pairs that succeeded.
    @discardableResult
    private func performTrash(_ urls: [URL]) -> [(original: URL, trashed: URL)] {
        guard !urls.isEmpty else { return [] }
        var moves: [(original: URL, trashed: URL)] = []
        var failure: String?
        for url in urls {
            var resulting: NSURL?
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
                if let trashed = resulting { moves.append((original: url, trashed: trashed as URL)) }
                starredPaths.remove(url.path)
                selection.remove(url)
            } catch {
                failure = (error as NSError).localizedDescription
            }
        }
        if !moves.isEmpty { persistStars() }
        if let failure { lastError = failure; NSSound.beep() }
        return moves
    }

    /// Undo of trash: move items from the Trash back to their original locations.
    private func performRestore(_ moves: [(original: URL, trashed: URL)]) {
        var restored: [URL] = []
        var failure: String?
        for move in moves {
            do {
                try FileManager.default.moveItem(at: move.trashed, to: move.original)
                restored.append(move.original)
            } catch {
                failure = (error as NSError).localizedDescription
            }
        }
        if !restored.isEmpty {
            // Redo = trash the same items again (fresh Trash URLs each time).
            undoManager.registerUndo(withTarget: self) { store in
                let moves = store.performTrash(restored)
                guard !moves.isEmpty else { return }
                store.registerRestoreUndo(for: moves)
                store.refresh()
            }
            undoManager.setActionName(actionName(forTrashCount: restored.count))
            selection = Set(restored)
            refresh()
        }
        if let failure { lastError = failure; NSSound.beep() }
    }

    private func registerRestoreUndo(for moves: [(original: URL, trashed: URL)]) {
        undoManager.registerUndo(withTarget: self) { store in
            store.performRestore(moves)
        }
        undoManager.setActionName(actionName(forTrashCount: moves.count))
    }

    private func actionName(forTrashCount count: Int) -> String {
        count > 1 ? "Move \(count) Items to Trash" : "Move to Trash"
    }

    // MARK: Rename primitive (shared by commit / undo / redo)

    /// Moves a file to a new name, migrating selection/star state and registering
    /// the inverse rename for undo (which in turn registers redo).
    private func performRename(from source: URL, to destination: URL) {
        guard FileManager.default.fileExists(atPath: source.path),
              !FileManager.default.fileExists(atPath: destination.path) else {
            NSSound.beep()
            return
        }
        do {
            try FileManager.default.moveItem(at: source, to: destination)
            if starredPaths.remove(source.path) != nil {
                starredPaths.insert(destination.path)
                persistStars()
            }
            selection.remove(source)
            selection.insert(destination)
            if selectionAnchor == source { selectionAnchor = destination }
            if selectionFocus == source { selectionFocus = destination }
            undoManager.registerUndo(withTarget: self) { store in
                store.performRename(from: destination, to: source)
            }
            undoManager.setActionName("Rename")
            refresh()
        } catch {
            lastError = (error as NSError).localizedDescription
            NSSound.beep()
        }
    }

    // MARK: - Keyboard

    /// Handles a key press from the panel's monitor. Returns `true` when the
    /// event was consumed and should not propagate further.
    func handleKeyDown(_ event: NSEvent) -> Bool {
        let cmd = event.modifierFlags.contains(.command)
        let shift = event.modifierFlags.contains(.shift)

        // While renaming, the text field owns the keyboard except for commit/cancel.
        if renamingFileID != nil {
            switch event.keyCode {
            case 36, 76: commitRename(); return true   // Return / Enter
            case 53: cancelRename(); return true        // Escape
            default: return false
            }
        }

        switch event.keyCode {
        case 51, 117:                                   // Delete / Forward Delete
            guard !selection.isEmpty else { return false }
            moveSelectionToTrash()
            return true
        case 36, 76:                                    // Return / Enter -> rename
            beginRenameSelection()
            return selection.count == 1
        case 49:                                        // Space -> Quick Look
            guard !selection.isEmpty else { return false }
            quickLookSelection()
            return true
        case 6 where cmd && shift:                      // ⇧⌘Z -> redo
            performRedo()
            return true
        case 6 where cmd:                               // ⌘Z -> undo
            performUndo()
            return true
        case 0 where cmd:                               // ⌘A -> select all
            selectAll()
            return true
        case 31 where cmd:                              // ⌘O -> open
            guard !selection.isEmpty else { return false }
            openSelection()
            return true
        case 123: moveSelection(.left, extend: shift); return true
        case 124: moveSelection(.right, extend: shift); return true
        case 125: moveSelection(.down, extend: shift); return true
        case 126: moveSelection(.up, extend: shift); return true
        default:
            return false
        }
    }

    // MARK: - Maintenance

    /// Drops selection / focus / rename state pointing at files that no longer exist.
    private func pruneTransientStateToCurrentFiles() {
        let existing = Set(files.map(\.url))
        selection.formIntersection(existing)
        if let a = selectionAnchor, !existing.contains(a) { selectionAnchor = nil }
        if let f = selectionFocus, !existing.contains(f) { selectionFocus = nil }
        if let r = renamingFileID, !existing.contains(r) { renamingFileID = nil }
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
                    self.pruneTransientStateToCurrentFiles()
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
