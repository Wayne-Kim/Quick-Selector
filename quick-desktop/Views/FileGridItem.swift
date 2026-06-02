import SwiftUI

struct FileGridItem: View {
    let file: DesktopFile

    private static let thumbSize = CGSize(width: 88, height: 88)

    @State private var image: NSImage?
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 6) {
            thumbnail
            Text(file.name)
                .font(.caption2)
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .frame(height: 28, alignment: .top)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovering ? Color.primary.opacity(0.08) : Color.clear)
        )
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
        .onTapGesture(count: 2) { openFile() }
        .contextMenu {
            Button("Open") { openFile() }
            Button("Reveal in Finder") { revealInFinder() }
            Button("Quick Look") { quickLook() }
            Divider()
            Button("Copy") { copyToPasteboard() }
            Divider()
            Button("Move to Trash", role: .destructive) { moveToTrash() }
        }
    }

    private func openFile() {
        NSWorkspace.shared.open(file.url)
    }

    private func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([file.url])
    }

    private func quickLook() {
        QuickLookController.shared.preview(file.url)
    }

    private func copyToPasteboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([file.url as NSURL])
    }

    private func moveToTrash() {
        try? FileManager.default.trashItem(at: file.url, resultingItemURL: nil)
    }

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
