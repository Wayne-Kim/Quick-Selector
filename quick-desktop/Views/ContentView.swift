import SwiftUI

struct ContentView: View {
    @ObservedObject var store: DesktopStore
    @ObservedObject var notes: NoteStore
    @ObservedObject var panel: PanelState

    var body: some View {
        VStack(spacing: 0) {
            header
            modePicker
            Divider()
            content
        }
        .frame(width: 360, height: 420)
        .onChange(of: panel.mode) { _ in
            // Leaving a half of the panel shouldn't silently drop what was
            // being typed in it.
            if store.renamingFileID != nil { store.commitRename() }
            notes.commitDraft()
        }
    }

    @ViewBuilder
    private var header: some View {
        switch panel.mode {
        case .files: filesHeader
        case .notes: notesHeader
        }
    }

    private var modePicker: some View {
        Picker("", selection: $panel.mode) {
            ForEach(PanelMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var content: some View {
        switch panel.mode {
        case .files: body(for: store)
        case .notes: NotesView(store: notes)
        }
    }

    private var notesHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "note.text")
                .foregroundStyle(.tint)
            Text("Notes")
                .font(.headline)
            Spacer()
            Text("\(notes.notes.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Button {
                notes.create()
            } label: {
                Image(systemName: "square.and.pencil")
            }
            .buttonStyle(.borderless)
            .help("New note (⌘N)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var filesHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.stack.3d.up.fill")
                .foregroundStyle(.tint)
            Text(store.folderName)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(store.folderURL.path)
            Spacer()
            Text(store.selection.isEmpty ? "\(store.files.count)" : "\(store.selection.count) selected")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Button {
                store.chooseFolder()
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Choose folder to track")
            Button {
                store.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func body(for store: DesktopStore) -> some View {
        if !store.hasAccess {
            permissionDenied
        } else if store.files.isEmpty {
            emptyState
        } else {
            fileList
        }
    }

    private var fileList: some View {
        ScrollView {
            LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 4) {
                ForEach(store.files) { file in
                    // Flags are resolved here and handed down as values, so
                    // SwiftUI can skip the cells a change didn't touch.
                    FileGridItem(
                        store: store,
                        file: file,
                        isSelected: store.selection.contains(file.url),
                        isStarred: store.isStarred(file),
                        isRenaming: store.renamingFileID == file.url
                    )
                    .equatable()
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .contentShape(Rectangle())
        .onTapGesture { store.clearSelection() }
    }

    private static let columns: [GridItem] = Array(
        repeating: GridItem(.flexible(), spacing: 4, alignment: .top),
        count: 3
    )

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("\(store.folderName) is empty")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var permissionDenied: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "lock.shield")
                .font(.system(size: 32))
                .foregroundStyle(.orange)
            Text("Folder access denied")
                .font(.headline)
            Text("Grant access in System Settings →\nPrivacy & Security → Files and Folders.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button("Choose Folder…") {
                    store.chooseFolder()
                }
            }
            .padding(.top, 4)
            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
    }

}
