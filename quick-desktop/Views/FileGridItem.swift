import SwiftUI

struct FileGridItem: View, Equatable {
    /// The store is held for actions only - the cell deliberately does *not*
    /// observe it. Everything it renders arrives as a plain value from the
    /// parent, so a selection change or a keystroke in the rename field
    /// repaints the cells that actually changed instead of all of them.
    let store: DesktopStore
    let file: DesktopFile
    let style: FileViewStyle
    let folderColor: Color?
    let isSelected: Bool
    let isStarred: Bool
    let isRenaming: Bool

    static func == (lhs: FileGridItem, rhs: FileGridItem) -> Bool {
        lhs.store === rhs.store
            && lhs.file == rhs.file
            && lhs.style == rhs.style
            && lhs.folderColor == rhs.folderColor
            && lhs.isSelected == rhs.isSelected
            && lhs.isStarred == rhs.isStarred
            && lhs.isRenaming == rhs.isRenaming
    }

    @State private var image: NSImage?
    @State private var isHovering = false

    private var thumbSize: CGSize { style.thumbnailSize }
    private var isCompact: Bool { style == .smallIcons }
    private var nameHeight: CGFloat { isCompact ? 14 : 28 }

    var body: some View {
        VStack(spacing: isCompact ? 3 : 6) {
            thumbnail
            nameLabel
        }
        .padding(isCompact ? 4 : 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .overlay(alignment: .topLeading) { folderDot }
        .overlay(alignment: .topTrailing) { starBadge }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .task(id: taskID) {
            image = await loadThumbnail(for: file, size: thumbSize)
        }
        .onDrag {
            NSItemProvider(contentsOf: file.url) ?? NSItemProvider()
        } preview: {
            dragPreview
        }
        // Single tap first, double click layered on simultaneously: chaining
        // two `onTapGesture`s makes the single one wait out the double-click
        // interval before the selection highlight appears.
        .onTapGesture { applyClick(store, to: file) }
        .simultaneousGesture(TapGesture(count: 2).onEnded { handleOpen() })
        .contextMenu { FileContextMenu(store: store, file: file) }
    }

    private var taskID: String { "\(file.url.path)#\(Int(thumbSize.width))" }

    // MARK: - Name / rename field

    @ViewBuilder
    private var nameLabel: some View {
        if isRenaming {
            RenameField(store: store, file: file, rename: store.rename, height: nameHeight)
        } else {
            Text(file.name)
                .font(isCompact ? .system(size: 9) : .caption2)
                .lineLimit(isCompact ? 1 : 2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .frame(height: nameHeight, alignment: .top)
        }
    }

    // MARK: - Badges

    @ViewBuilder
    private var folderDot: some View {
        if let folderColor {
            FolderDot(color: folderColor, diameter: isCompact ? 6 : 7)
                .padding(isCompact ? 3 : 5)
        }
    }

    @ViewBuilder
    private var starBadge: some View {
        if isStarred || isHovering {
            StarBadge(store: store, file: file, isStarred: isStarred, size: isCompact ? 8 : 11)
                .padding(isCompact ? 2 : 4)
        }
    }

    private var backgroundFill: Color {
        if isSelected { return Color.accentColor.opacity(0.18) }
        if isHovering { return Color.primary.opacity(0.08) }
        return .clear
    }

    private func handleOpen() {
        store.select(file)
        NSWorkspace.shared.open(file.url)
    }

    // MARK: - Thumbnail

    private var dragPreview: some View {
        let resolved = resolvedThumbnail(for: file, size: thumbSize, loaded: image)
        return Image(nsImage: resolved.image)
            .resizable()
            .interpolation(.medium)
            .aspectRatio(contentMode: .fit)
            .frame(width: thumbSize.width, height: thumbSize.height)
    }

    /// What to draw right now: the generated thumbnail if we have one (from
    /// this cell's own load or from the cache a prewarm filled), otherwise a
    /// generic type icon. Never a spinner - an animated indeterminate
    /// `ProgressView` per pending cell is a lot of CoreAnimation work for
    /// something that is on screen for a fraction of a second.
    private var thumbnail: some View {
        let resolved = resolvedThumbnail(for: file, size: thumbSize, loaded: image)
        return ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.05))
            Image(nsImage: resolved.image)
                .resizable()
                .interpolation(.medium)
                .aspectRatio(contentMode: .fit)
                .padding(resolved.isPlaceholder ? (isCompact ? 8 : 20) : 2)
                .opacity(resolved.isPlaceholder ? 0.65 : 1)
        }
        .frame(width: thumbSize.width, height: thumbSize.height)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
    }
}
