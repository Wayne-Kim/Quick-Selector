import SwiftUI

struct FileRow: View, Equatable {
    let store: DesktopStore
    let file: DesktopFile
    let folderColor: Color?
    let isSelected: Bool
    let isStarred: Bool
    let isRenaming: Bool
    let metaText: String

    static func == (lhs: FileRow, rhs: FileRow) -> Bool {
        lhs.store === rhs.store
            && lhs.file == rhs.file
            && lhs.folderColor == rhs.folderColor
            && lhs.isSelected == rhs.isSelected
            && lhs.isStarred == rhs.isStarred
            && lhs.isRenaming == rhs.isRenaming
            && lhs.metaText == rhs.metaText
    }

    private static let iconSize = FileViewStyle.list.thumbnailSize

    @State private var image: NSImage?
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            if let folderColor {
                FolderDot(color: folderColor, diameter: 7)
            }
            icon
            name
            Spacer(minLength: 6)
            if isStarred || isHovering {
                StarBadge(store: store, file: file, isStarred: isStarred, size: 10, showsBackground: false)
            }
            Text(metaText)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .fixedSize()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(backgroundFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .task(id: file.url.path) {
            image = await loadThumbnail(for: file, size: Self.iconSize)
        }
        .onDrag {
            NSItemProvider(contentsOf: file.url) ?? NSItemProvider()
        } preview: {
            dragPreview
        }
        .onTapGesture { applyClick(store, to: file) }
        .simultaneousGesture(TapGesture(count: 2).onEnded { handleOpen() })
        .contextMenu { FileContextMenu(store: store, file: file) }
    }

    @ViewBuilder
    private var name: some View {
        if isRenaming {
            RenameField(store: store, file: file, rename: store.rename, height: 22)
        } else {
            Text(file.name)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var icon: some View {
        let resolved = resolvedThumbnail(for: file, size: Self.iconSize, loaded: image)
        return Image(nsImage: resolved.image)
            .resizable()
            .interpolation(.medium)
            .aspectRatio(contentMode: .fit)
            .frame(width: Self.iconSize.width, height: Self.iconSize.height)
            .opacity(resolved.isPlaceholder ? 0.8 : 1)
    }

    private var dragPreview: some View {
        let resolved = resolvedThumbnail(for: file, size: Self.iconSize, loaded: image)
        return Image(nsImage: resolved.image)
            .resizable()
            .interpolation(.medium)
            .aspectRatio(contentMode: .fit)
            .frame(width: 48, height: 48)
    }

    private var backgroundFill: Color {
        if isSelected { return Color.accentColor.opacity(0.18) }
        if isHovering { return Color.primary.opacity(0.07) }
        return .clear
    }

    private func handleOpen() {
        store.select(file)
        NSWorkspace.shared.open(file.url)
    }
}
