import SwiftUI

struct FileGridItem: View {
    @ObservedObject var store: DesktopStore
    let file: DesktopFile

    private static let thumbSize = CGSize(width: 88, height: 88)

    @State private var image: NSImage?
    @State private var isHovering = false
    @FocusState private var renameFieldFocused: Bool

    private var isSelected: Bool { store.isSelected(file) }
    private var isStarred: Bool { store.isStarred(file) }
    private var isRenaming: Bool { store.renamingFileID == file.url }

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
        .task(id: file.id) {
            await loadThumbnail()
        }
        .onDrag {
            NSItemProvider(contentsOf: file.url) ?? NSItemProvider()
        } preview: {
            dragPreview
        }
        .onTapGesture(count: 2) { handleOpen() }
        .onTapGesture(count: 1) { handleClick() }
        .contextMenu { contextMenuContent }
    }

    // MARK: - Name / rename field

    @ViewBuilder
    private var nameLabel: some View {
        if isRenaming {
            HStack(spacing: 1) {
                TextField("", text: $store.renameText)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption2)
                    .lineLimit(1)
                    .focused($renameFieldFocused)
                    .onSubmit { store.commitRename() }
                    .onExitCommand { store.cancelRename() }
                    .onAppear { focusRenameField() }
                if !store.renameExtension.isEmpty {
                    Text("." + store.renameExtension)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .frame(height: 28)
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

    /// Moves keyboard focus into the rename field once it is in the key panel's
    /// responder chain. Setting `@FocusState` synchronously in `.onAppear` is
    /// too early, so we assert it on the next run loop and re-assert shortly
    /// after in case the field editor wasn't ready on the first pass.
    private func focusRenameField() {
        DispatchQueue.main.async { renameFieldFocused = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            if store.renamingFileID == file.url { renameFieldFocused = true }
        }
    }

    // MARK: - Context menu

    @ViewBuilder
    private var contextMenuContent: some View {
        if isSelected && store.selection.count > 1 {
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
            Button(isStarred ? "Remove Star" : "Add Star") { store.toggleStar(file) }
            Divider()
            Button("Move to Trash", role: .destructive) { store.trash([file.url]) }
        }
    }

    private func copyToPasteboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([file.url as NSURL])
    }

    // MARK: - Thumbnail

    @ViewBuilder
    private var dragPreview: some View {
        if let nsImage = image {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.medium)
                .aspectRatio(contentMode: .fit)
                .frame(width: Self.thumbSize.width, height: Self.thumbSize.height)
        } else {
            Image(systemName: file.isDirectory ? "folder.fill" : "doc.fill")
                .font(.system(size: 48))
                .frame(width: Self.thumbSize.width, height: Self.thumbSize.height)
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.05))
            if let nsImage = image {
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.medium)
                    .aspectRatio(contentMode: .fit)
                    .padding(2)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .opacity(0.5)
            }
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
