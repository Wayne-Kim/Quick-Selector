import SwiftUI

@MainActor
func resolvedThumbnail(for file: TrackedFile, size: CGSize, loaded: NSImage?) -> (image: NSImage, isPlaceholder: Bool) {
    if let loaded { return (loaded, false) }
    if let hit = ThumbnailCache.shared.cached(for: file, size: size) { return (hit, false) }
    return (ThumbnailCache.shared.placeholder(for: file), true)
}

@MainActor
func loadThumbnail(for file: TrackedFile, size: CGSize) async -> NSImage {
    if let cached = ThumbnailCache.shared.cached(for: file, size: size) { return cached }
    let scale = NSScreen.main?.backingScaleFactor ?? 2
    return await ThumbnailCache.shared.thumbnail(for: file, size: size, scale: scale)
}

struct FolderDot: View {
    let color: Color
    var diameter: CGFloat = 7

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: diameter, height: diameter)
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5))
    }
}

struct StarBadge: View {
    let store: FileStore
    let file: TrackedFile
    let isStarred: Bool
    var size: CGFloat = 11
    var showsBackground: Bool = true

    var body: some View {
        Button {
            store.toggleStar(file)
        } label: {
            Image(systemName: isStarred ? "star.fill" : "star")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(isStarred ? Color.yellow : Color.secondary)
                .padding(showsBackground ? 3 : 0)
                .background {
                    if showsBackground { Circle().fill(.regularMaterial) }
                }
        }
        .buttonStyle(.plain)
        .help(isStarred ? "Remove star" : "Mark with a star")
    }
}

/// Resolves the click modifiers the grid and the list both interpret the same way.
@MainActor
func applyClick(_ store: FileStore, to file: TrackedFile) {
    let modifiers = NSEvent.modifierFlags
    if modifiers.contains(.command) {
        store.toggle(file)
    } else if modifiers.contains(.shift) {
        store.extendSelection(to: file)
    } else {
        store.select(file)
    }
}

/// The inline rename editor. Split out so that observing `RenameState` - which
/// changes on every keystroke - invalidates this field and nothing else.
struct RenameField: View {
    let store: FileStore
    let file: TrackedFile
    @ObservedObject var rename: RenameState
    var height: CGFloat = 28

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
        .frame(height: height)
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

/// Built only when the menu is actually opened, so reading live selection state
/// here costs nothing while the grid is just sitting there.
struct FileContextMenu: View {
    @ObservedObject var store: FileStore
    let file: TrackedFile

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
