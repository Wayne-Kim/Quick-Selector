import SwiftUI

struct FileGridItem: View, Equatable {
    /// The store is held for actions only — the cell deliberately does *not*
    /// observe it. Everything it renders arrives as a plain value from the
    /// parent, so a selection change or a keystroke in the rename field
    /// repaints the cells that actually changed instead of all of them.
    let store: DesktopStore
    let file: DesktopFile
    let isSelected: Bool
    let isStarred: Bool
    let isRenaming: Bool

    static func == (lhs: FileGridItem, rhs: FileGridItem) -> Bool {
        lhs.store === rhs.store
            && lhs.file == rhs.file
            && lhs.isSelected == rhs.isSelected
            && lhs.isStarred == rhs.isStarred
            && lhs.isRenaming == rhs.isRenaming
    }

    private static let thumbSize = ThumbnailCache.gridSize

    @State private var image: NSImage?
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 6) {
            thumbnail
            nameLabel
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .overlay(alignment: .topTrailing) { starBadge }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .task(id: file) {
            await loadThumbnail()
        }
        .onDrag {
            FileDragSource.itemProvider(for: file.url)
        } preview: {
            dragPreview
        }
        // Single tap first, double click layered on simultaneously: chaining
        // two `onTapGesture`s makes the single one wait out the double-click
        // interval before the selection highlight appears.
        .onTapGesture { handleClick() }
        .simultaneousGesture(TapGesture(count: 2).onEnded { handleOpen() })
        .contextMenu { FileContextMenu(store: store, file: file) }
    }

    // MARK: - Name / rename field

    @ViewBuilder
    private var nameLabel: some View {
        if isRenaming {
            RenameField(store: store, file: file, rename: store.rename)
        } else {
            Text(file.name)
                .font(.caption2)
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .frame(height: 28, alignment: .top)
        }
    }

    // MARK: - Star

    @ViewBuilder
    private var starBadge: some View {
        if isStarred || isHovering {
            Button {
                store.toggleStar(file)
            } label: {
                Image(systemName: isStarred ? "star.fill" : "star")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isStarred ? Color.yellow : Color.secondary)
                    .padding(3)
                    .background(.regularMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .help(isStarred ? "Remove star" : "Mark with a star")
            .padding(4)
        }
    }

    private var backgroundFill: Color {
        if isSelected { return Color.accentColor.opacity(0.18) }
        if isHovering { return Color.primary.opacity(0.08) }
        return .clear
    }

    // MARK: - Interaction

    private func handleClick() {
        let mods = NSEvent.modifierFlags
        if mods.contains(.command) {
            store.toggle(file)
        } else if mods.contains(.shift) {
            store.extendSelection(to: file)
        } else {
            store.select(file)
        }
    }

    private func handleOpen() {
        store.select(file)
        NSWorkspace.shared.open(file.url)
    }

    // MARK: - Thumbnail

    /// What to draw right now: the generated thumbnail if we have one (from
    /// this cell's own load or from the cache a prewarm filled), otherwise a
    /// generic type icon. Never a spinner — an animated indeterminate
    /// `ProgressView` per pending cell is a lot of CoreAnimation work for
    /// something that is on screen for a fraction of a second.
    private var resolvedImage: (image: NSImage, isPlaceholder: Bool) {
        if let image { return (image, false) }
        if let hit = ThumbnailCache.shared.cached(for: file, size: Self.thumbSize) {
            return (hit, false)
        }
        return (ThumbnailCache.shared.placeholder(for: file), true)
    }

    private var dragPreview: some View {
        let resolved = resolvedImage
        return Image(nsImage: resolved.image)
            .resizable()
            .interpolation(.medium)
            .aspectRatio(contentMode: .fit)
            .frame(width: Self.thumbSize.width, height: Self.thumbSize.height)
    }

    private var thumbnail: some View {
        let resolved = resolvedImage
        return ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.05))
            Image(nsImage: resolved.image)
                .resizable()
                .interpolation(.medium)
                .aspectRatio(contentMode: .fit)
                .padding(resolved.isPlaceholder ? 20 : 2)
                .opacity(resolved.isPlaceholder ? 0.65 : 1)
        }
        .frame(width: Self.thumbSize.width, height: Self.thumbSize.height)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }

    private func loadThumbnail() async {
        if let cached = ThumbnailCache.shared.cached(for: file, size: Self.thumbSize) {
            image = cached
            return
        }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let result = await ThumbnailCache.shared.thumbnail(for: file, size: Self.thumbSize, scale: scale)
        image = result
    }
}

// MARK: - Rename field

/// The inline rename editor. Split out so that observing `RenameState` — which
/// changes on every keystroke — invalidates this field and nothing else.
private struct RenameField: View {
    let store: DesktopStore
    let file: DesktopFile
    @ObservedObject var rename: RenameState

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 1) {
            TextField("", text: $rename.text)
                .textFieldStyle(.roundedBorder)
                .font(.caption2)
                .lineLimit(1)
                .focused($isFocused)
                .onSubmit { store.commitRename() }
                .onExitCommand { store.cancelRename() }
                .onAppear { focusField() }
            if !rename.fileExtension.isEmpty {
                Text("." + rename.fileExtension)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .frame(height: 28)
    }

    /// Moves keyboard focus into the rename field once it is in the key panel's
    /// responder chain. Setting `@FocusState` synchronously in `.onAppear` is
    /// too early, so we assert it on the next run loop and re-assert shortly
    /// after in case the field editor wasn't ready on the first pass.
    private func focusField() {
        DispatchQueue.main.async { isFocused = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            if store.renamingFileID == file.url { isFocused = true }
        }
    }
}

// MARK: - Context menu

/// Built only when the menu is actually opened, so reading live selection state
/// here costs nothing while the grid is just sitting there.
private struct FileContextMenu: View {
    @ObservedObject var store: DesktopStore
    let file: DesktopFile

    var body: some View {
        if store.isSelected(file) && store.selection.count > 1 {
            let count = store.selection.count
            Button("Open \(count) Items") { store.openSelection() }
            Button("Reveal in Finder") { store.revealSelection() }
            Button("Quick Look") { store.quickLookSelection() }
            Divider()
            Button("Copy") { store.copySelection() }
            Button(store.allSelectionStarred ? "Remove Stars" : "Add Stars") {
                store.toggleStarForSelection()
            }
            Divider()
            Button("Move \(count) Items to Trash", role: .destructive) {
                store.moveSelectionToTrash()
            }
        } else {
            Button("Open") { NSWorkspace.shared.open(file.url) }
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
            Button("Quick Look") { QuickLookController.shared.preview(file.url) }
            Button("Rename") { store.beginRename(file) }
            Divider()
            Button("Copy") { copyToPasteboard() }
            Button(store.isStarred(file) ? "Remove Star" : "Add Star") { store.toggleStar(file) }
            Divider()
            Button("Move to Trash", role: .destructive) { store.trash([file.url]) }
        }
    }

    private func copyToPasteboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([file.url as NSURL])
    }
}
