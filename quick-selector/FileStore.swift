import Foundation
import Combine
import AppKit

/// One block of the file list: a single merged block, or one block per tracked
/// folder when the panel is grouped by folder.
struct FileSection: Identifiable, Equatable {
    let folder: TrackedFolder?
    let files: [TrackedFile]

    var id: String { folder?.path ?? "all" }
}

struct FolderLoadFailure: Equatable {
    let message: String
    let isPermissionDenied: Bool
}

@MainActor
final class FileStore: ObservableObject {
    @Published private(set) var sections: [FileSection] = []
    /// Every file in display order, flattened across sections. Selection and
    /// keyboard navigation work off this order.
    @Published private(set) var files: [TrackedFile] = []
    @Published private(set) var failures: [String: FolderLoadFailure] = [:]
    @Published private(set) var lastError: String?

    /// URLs of the currently selected files.
    @Published var selection: Set<URL> = []
    /// Absolute paths of files the user has starred ("to use this time").
    @Published private(set) var starredPaths: Set<String> = []
    /// The file currently being renamed inline, if any.
    @Published var renamingFileID: URL?
    /// State of the inline rename field. Deliberately a separate observable
    /// object: typing changes it many times per second, and only the field
    /// itself should repaint - not every cell in the grid.
    let rename = RenameState()

    let registry: FolderRegistry
    let options: DisplayOptions

    /// Anchor of a shift/range selection; stays put while the focus end moves.
    private var selectionAnchor: URL?
    /// The moving end of the selection (the "cursor" for arrow navigation).
    private var selectionFocus: URL?

    /// Undo stack for reversible file operations (Trash / Rename).
    private let undoManager = UndoManager()

    private var scans: [String: [TrackedFile]] = [:]
    private var observers: [String: FolderObserver] = [:]
    private var refreshTasks: [String: Task<Void, Never>] = [:]
    private var refreshQueued: Set<String> = []
    private var cancellables: Set<AnyCancellable> = []

    private static let starredDefaultsKey = "starredFilePaths"

    init(registry: FolderRegistry, options: DisplayOptions) {
        self.registry = registry
        self.options = options
        self.starredPaths = Set(UserDefaults.standard.stringArray(forKey: Self.starredDefaultsKey) ?? [])

        registry.$folders
            .sink { [weak self] folders in
                Task { @MainActor in self?.syncFolders(folders) }
            }
            .store(in: &cancellables)

        // `objectWillChange` fires before the new value lands, so the rebuild
        // is deferred a turn to read the option the user just picked.
        options.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in self?.rebuild() }
            }
            .store(in: &cancellables)
    }

    /// Number of columns the grid draws, so vertical arrow navigation lands on
    /// the right neighbour.
    var columnCount: Int { options.viewStyle.columnCount }

    var deniedFolders: [TrackedFolder] {
        registry.folders.filter { failures[$0.path]?.isPermissionDenied == true }
    }

    var hasAccess: Bool {
        registry.folders.isEmpty || deniedFolders.count < registry.folders.count
    }

    /// Folders that failed to load, in tracked order, for the inline warning.
    var failedFolders: [TrackedFolder] {
        registry.folders.filter { failures[$0.path] != nil }
    }

    // MARK: - Folder set

    private func syncFolders(_ folders: [TrackedFolder]) {
        let paths = Set(folders.map(\.path))

        for (path, observer) in observers where !paths.contains(path) {
            observer.stop()
            observers[path] = nil
            scans[path] = nil
            failures[path] = nil
            refreshTasks[path]?.cancel()
            refreshTasks[path] = nil
            refreshQueued.remove(path)
        }

        for folder in folders where observers[folder.path] == nil {
            startObserving(folder.path)
            refreshFolder(folder.path)
        }

        rebuild()
    }

    // MARK: - Selection

    func isSelected(_ file: TrackedFile) -> Bool { selection.contains(file.url) }

    /// Selected files in current display order (so actions respect the on-screen order).
    var orderedSelectionURLs: [URL] { files.filter { selection.contains($0.url) }.map(\.url) }

    /// Replaces the selection with a single file and resets the range anchor.
    func select(_ file: TrackedFile) {
        commitRenameIfNeeded()
        selection = [file.url]
        selectionAnchor = file.url
        selectionFocus = file.url
    }

    /// Adds/removes a single file from the selection (⌘-click).
    func toggle(_ file: TrackedFile) {
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
    func extendSelection(to file: TrackedFile) {
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
        guard let current = cursor, let index = files.firstIndex(where: { $0.url == current }) else {
            select(files[0])
            return
        }
        guard let target = targetIndex(from: index, direction: direction) else { return }
        if extend { extendSelection(to: files[target]) } else { select(files[target]) }
    }

    private func targetIndex(from index: Int, direction: MoveDirection) -> Int? {
        switch direction {
        case .left: return index > 0 ? index - 1 : nil
        case .right: return index + 1 < files.count ? index + 1 : nil
        case .up: return verticalTarget(from: index, goingDown: false)
        case .down: return verticalTarget(from: index, goingDown: true)
        }
    }

    /// Vertical steps stay inside the file's own section, because each section
    /// starts a fresh row. Stepping off either end lands on the neighbouring
    /// section instead of skipping a screenful.
    private func verticalTarget(from index: Int, goingDown: Bool) -> Int? {
        guard let position = sectionPosition(of: index) else { return nil }
        let count = sections[position.section].files.count
        let step = goingDown ? columnCount : -columnCount
        let next = position.indexInSection + step
        if next >= 0, next < count { return position.offset + next }
        if goingDown {
            let sectionEnd = position.offset + count
            return sectionEnd < files.count ? sectionEnd : nil
        }
        return position.offset > 0 ? position.offset - 1 : nil
    }

    private func sectionPosition(of index: Int) -> (section: Int, offset: Int, indexInSection: Int)? {
        var offset = 0
        for (sectionIndex, section) in sections.enumerated() {
            if index < offset + section.files.count {
                return (sectionIndex, offset, index - offset)
            }
            offset += section.files.count
        }
        return nil
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
        refreshFolders(containing: moves.map { $0.original })
    }

    // MARK: - Stars

    func isStarred(_ file: TrackedFile) -> Bool { starredPaths.contains(file.url.path) }

    /// `true` when every selected file is already starred (drives the toggle's label).
    var allSelectionStarred: Bool {
        !selection.isEmpty && selection.allSatisfy { starredPaths.contains($0.path) }
    }

    func toggleStar(_ file: TrackedFile) {
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

    func beginRename(_ file: TrackedFile) {
        commitRenameIfNeeded()
        selection = [file.url]
        selectionAnchor = file.url
        selectionFocus = file.url
        // Lock the extension: only the base name is editable so the file type
        // can't be changed by accident. Directories have no protected extension.
        let ext = file.isDirectory ? "" : file.url.pathExtension
        rename.fileExtension = ext
        rename.text = ext.isEmpty ? file.name : file.url.deletingPathExtension().lastPathComponent
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
        let base = rename.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty, !base.contains("/"), !base.contains(":") else { return }
        let ext = rename.fileExtension
        let newName = ext.isEmpty ? base : "\(base).\(ext)"
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
        // Collected first, then applied in one shot: mutating `starredPaths` /
        // `selection` per file would repaint the grid once per trashed item.
        var trashedPaths: Set<String> = []
        var trashedURLs: Set<URL> = []
        for url in urls {
            var resulting: NSURL?
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
                if let trashed = resulting { moves.append((original: url, trashed: trashed as URL)) }
                trashedPaths.insert(url.path)
                trashedURLs.insert(url)
            } catch {
                failure = (error as NSError).localizedDescription
            }
        }
        if !starredPaths.isDisjoint(with: trashedPaths) {
            starredPaths.subtract(trashedPaths)
            persistStars()
        }
        if !selection.isDisjoint(with: trashedURLs) {
            selection.subtract(trashedURLs)
        }
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
                store.refreshFolders(containing: restored)
            }
            undoManager.setActionName(actionName(forTrashCount: restored.count))
            selection = Set(restored)
            refreshFolders(containing: restored)
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
            refreshFolders(containing: [source, destination])
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
        if !selection.isSubset(of: existing) { selection.formIntersection(existing) }
        if let a = selectionAnchor, !existing.contains(a) { selectionAnchor = nil }
        if let f = selectionFocus, !existing.contains(f) { selectionFocus = nil }
        if let r = renamingFileID, !existing.contains(r) { renamingFileID = nil }
    }

    // MARK: - Observing

    private func startObserving(_ path: String) {
        observers[path]?.stop()
        let observer = FolderObserver(url: URL(fileURLWithPath: path)) { [weak self] in
            Task { @MainActor in
                self?.refreshFolder(path)
            }
        }
        observer.start()
        observers[path] = observer
    }

    // MARK: - Loading

    func refresh() {
        for folder in registry.folders { refreshFolder(folder.path) }
    }

    private func refreshFolders(containing urls: [URL]) {
        let paths = Set(urls.map { $0.deletingLastPathComponent().standardizedFileURL.path })
        let tracked = registry.folders.map(\.path).filter { paths.contains($0) }
        if tracked.isEmpty {
            refresh()
        } else {
            for path in tracked { refreshFolder(path) }
        }
    }

    /// Reloads one folder. A second request while a scan is running is folded
    /// into a single follow-up scan instead of piling up.
    private func refreshFolder(_ path: String) {
        guard refreshTasks[path] == nil else {
            refreshQueued.insert(path)
            return
        }
        let url = URL(fileURLWithPath: path)
        refreshTasks[path] = Task { @MainActor [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Self.loadFiles(at: url)
            }.value
            guard let self else { return }
            self.refreshTasks[path] = nil
            defer {
                if self.refreshQueued.remove(path) != nil { self.refreshFolder(path) }
            }
            // Ignore results for a folder that is no longer tracked.
            guard self.registry.folder(atPath: path) != nil else { return }
            self.apply(result, for: path)
        }
    }

    private func apply(_ result: Result<[TrackedFile], Error>, for path: String) {
        switch result {
        case .success(let loaded):
            if scans[path] != loaded { scans[path] = loaded }
            if failures[path] != nil { failures[path] = nil }
            if lastError != nil { lastError = nil }
        case .failure(let error):
            if scans[path]?.isEmpty == false { scans[path] = [] }
            let ns = error as NSError
            let denied = ns.domain == NSCocoaErrorDomain
                && (ns.code == NSFileReadNoPermissionError || ns.code == 257)
            let failure = FolderLoadFailure(message: ns.localizedDescription, isPermissionDenied: denied)
            if failures[path] != failure { failures[path] = failure }
        }
        rebuild()
    }

    /// Publishes the merged, sorted result, touching `@Published` state only
    /// where it actually differs - every mutation here rebuilds the whole grid,
    /// and most scans find nothing new at all.
    private func rebuild() {
        let next = makeSections()
        guard next != sections else {
            prewarmThumbnails()
            return
        }
        sections = next
        files = next.flatMap(\.files)
        pruneTransientStateToCurrentFiles()
        prewarmThumbnails()
    }

    private func makeSections() -> [FileSection] {
        let folders = registry.folders
        switch options.grouping {
        case .merged:
            let merged = folders.flatMap { scans[$0.path] ?? [] }
            return [FileSection(folder: nil, files: sorted(merged))]
        case .byFolder:
            return folders.map { FileSection(folder: $0, files: sorted(scans[$0.path] ?? [])) }
        }
    }

    private func sorted(_ items: [TrackedFile]) -> [TrackedFile] {
        items.sorted { isOrderedBefore($0, $1) }
    }

    private func isOrderedBefore(_ lhs: TrackedFile, _ rhs: TrackedFile) -> Bool {
        switch options.sortKey {
        case .dateModified where lhs.modifiedAt != rhs.modifiedAt:
            return inChosenOrder(lhs.modifiedAt < rhs.modifiedAt)
        case .size where lhs.size != rhs.size:
            return inChosenOrder(lhs.size < rhs.size)
        case .kind where lhs.kind != rhs.kind:
            return inChosenOrder(lhs.kind < rhs.kind)
        case .name:
            let comparison = lhs.name.localizedStandardCompare(rhs.name)
            if comparison != .orderedSame { return inChosenOrder(comparison == .orderedAscending) }
        default:
            break
        }
        let byName = lhs.name.localizedStandardCompare(rhs.name)
        if byName != .orderedSame { return byName == .orderedAscending }
        return lhs.url.path < rhs.url.path
    }

    private func inChosenOrder(_ ascendingResult: Bool) -> Bool {
        options.ascending ? ascendingResult : !ascendingResult
    }

    /// Generates the first screenful of thumbnails ahead of time so the panel
    /// opens with images rather than filling in after the fact.
    private func prewarmThumbnails() {
        let style = options.viewStyle
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        ThumbnailCache.shared.prewarm(
            files.prefix(style.prewarmCount),
            size: style.thumbnailSize,
            scale: scale
        )
    }

    nonisolated private static func loadFiles(at url: URL) -> Result<[TrackedFile], Error> {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [
            .contentModificationDateKey,
            .fileSizeKey,
            .isDirectoryKey,
            .isHiddenKey,
            .nameKey,
        ]
        let folderPath = url.standardizedFileURL.path
        do {
            let urls = try fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
            var items: [TrackedFile] = []
            items.reserveCapacity(urls.count)
            for fileURL in urls {
                let name = fileURL.lastPathComponent
                if name.hasPrefix(".") { continue }
                if name == "Icon\r" { continue }
                let values = try? fileURL.resourceValues(forKeys: Set(keys))
                let mtime = values?.contentModificationDate ?? .distantPast
                let size = Int64(values?.fileSize ?? 0)
                let isDir = values?.isDirectory ?? false
                items.append(TrackedFile(
                    url: fileURL,
                    name: name,
                    modifiedAt: mtime,
                    size: size,
                    isDirectory: isDir,
                    folderPath: folderPath
                ))
            }
            return .success(items)
        } catch {
            return .failure(error)
        }
    }
}

/// The inline rename field's editing state, kept out of `FileStore` so that
/// each keystroke notifies only the text field.
@MainActor
final class RenameState: ObservableObject {
    /// The edited base name (without the extension).
    @Published var text: String = ""
    /// The renamed file's extension, without the dot; locked so the file type
    /// can't be changed by accident. Empty for directories and extension-less files.
    @Published fileprivate(set) var fileExtension: String = ""
}
