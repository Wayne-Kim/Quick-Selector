import SwiftUI

struct FileListView: View {
    @ObservedObject var store: FileStore
    @ObservedObject var options: DisplayOptions

    var body: some View {
        let colors = folderColors
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(store.sections) { section in
                    if let folder = section.folder {
                        sectionHeader(folder, count: section.files.count)
                    }
                    if section.files.isEmpty {
                        emptySectionNote
                    } else {
                        sectionBody(section, colors: colors)
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .contentShape(Rectangle())
        .onTapGesture { store.clearSelection() }
    }

    @ViewBuilder
    private func sectionBody(_ section: FileSection, colors: [String: Color]) -> some View {
        switch options.viewStyle {
        case .largeIcons, .smallIcons:
            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 4) {
                ForEach(section.files) { file in
                    // Flags are resolved here and handed down as values, so
                    // SwiftUI can skip the cells a change didn't touch.
                    FileGridItem(
                        store: store,
                        file: file,
                        style: options.viewStyle,
                        folderColor: colors[file.folderPath],
                        isSelected: store.selection.contains(file.url),
                        isStarred: store.isStarred(file),
                        isRenaming: store.renamingFileID == file.url
                    )
                    .equatable()
                }
            }
            .padding(.horizontal, 8)
        case .list:
            LazyVStack(spacing: 2) {
                ForEach(section.files) { file in
                    FileRow(
                        store: store,
                        file: file,
                        folderColor: colors[file.folderPath],
                        isSelected: store.selection.contains(file.url),
                        isStarred: store.isStarred(file),
                        isRenaming: store.renamingFileID == file.url,
                        metaText: metaText(for: file)
                    )
                    .equatable()
                }
            }
            .padding(.horizontal, 6)
        }
    }

    private func sectionHeader(_ folder: TrackedFolder, count: Int) -> some View {
        HStack(spacing: 6) {
            FolderDot(color: folder.color)
            Text(folder.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Text("\(count)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .opacity(0.7)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var emptySectionNote: some View {
        Text("Empty")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.bottom, 6)
    }

    private var gridColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: 4, alignment: .top),
            count: options.viewStyle.columnCount
        )
    }

    /// Dots are a merged-list affordance; grouped sections already say which
    /// folder a file came from, and a single folder has nothing to tell apart.
    private var folderColors: [String: Color] {
        guard options.grouping == .merged, store.registry.folders.count > 1 else { return [:] }
        return Dictionary(
            uniqueKeysWithValues: store.registry.folders.map { ($0.path, $0.color) }
        )
    }

    private func metaText(for file: TrackedFile) -> String {
        switch options.sortKey {
        case .size:
            return file.isDirectory ? "--" : ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file)
        case .kind:
            if file.isDirectory { return "Folder" }
            return file.kind.isEmpty ? "--" : file.kind.uppercased()
        case .dateModified, .name:
            return Self.dateText(file.modifiedAt)
        }
    }

    private static func dateText(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(.dateTime.month(.defaultDigits).day())
    }
}
