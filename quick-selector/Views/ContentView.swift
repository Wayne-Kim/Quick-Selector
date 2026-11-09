import SwiftUI

struct ContentView: View {
    @ObservedObject var store: FileStore
    @ObservedObject var registry: FolderRegistry
    @ObservedObject var options: DisplayOptions
    @ObservedObject var notes: NoteStore
    @ObservedObject var sites: SiteStore
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
            sites.cancelRecording()
        }
    }

    @ViewBuilder
    private var header: some View {
        switch panel.mode {
        case .files: filesHeader
        case .notes: notesHeader
        case .sites: sitesHeader
        case .shortcuts: shortcutsHeader
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
        case .files: filesContent
        case .notes: NotesView(store: notes)
        case .sites: SitesView(store: sites)
        case .shortcuts: ShortcutsView(store: sites)
        }
    }

    private var shortcutsHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "command")
                .foregroundStyle(.tint)
            Text("Shortcuts")
                .font(.headline)
            Spacer()
            Text("\(sites.sites.filter { $0.shortcut != nil }.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var sitesHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "globe")
                .foregroundStyle(.tint)
            Text("Sites")
                .font(.headline)
            Spacer()
            Text("\(sites.sites.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
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

    // MARK: - Files header

    private var filesHeader: some View {
        HStack(spacing: 6) {
            folderSummary
            Spacer(minLength: 4)
            countLabel
            folderMenu
            viewMenu
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
    private var folderSummary: some View {
        if registry.folders.isEmpty {
            Text("No folders")
                .font(.headline)
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 8) {
                ForEach(namedFolders) { folder in
                    HStack(spacing: 4) {
                        FolderDot(color: folder.color)
                        Text(folder.name)
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                if unnamedFolderCount > 0 {
                    Text("+\(unnamedFolderCount)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .help(registry.folders.map(\.path).joined(separator: "\n"))
        }
    }

    /// The header has room for two names; the rest are counted instead.
    private var namedFolders: [TrackedFolder] { Array(registry.folders.prefix(2)) }

    private var unnamedFolderCount: Int { max(0, registry.folders.count - 2) }

    private var countLabel: some View {
        Text(store.selection.isEmpty ? "\(store.files.count)" : "\(store.selection.count) selected")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .fixedSize()
    }

    private var folderMenu: some View {
        Menu {
            Section("Tracked Folders") {
                ForEach(registry.folders) { folder in
                    Toggle(isOn: trackingBinding(for: folder)) {
                        Text(folder.name)
                    }
                }
            }
            Divider()
            Button("Add Folder...") { registry.chooseFolder() }
            Button("Reset to Desktop Only") { registry.resetToDesktopOnly() }
                .disabled(registry.isDesktopOnly)
        } label: {
            Image(systemName: "folder")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Tracked folders")
    }

    private func trackingBinding(for folder: TrackedFolder) -> Binding<Bool> {
        Binding(
            get: { true },
            set: { isTracked in
                if !isTracked { registry.remove(folder) }
            }
        )
    }

    private var viewMenu: some View {
        Menu {
            Picker("Group", selection: $options.grouping) {
                ForEach(FileGrouping.allCases) { grouping in
                    Text(grouping.title).tag(grouping)
                }
            }
            .pickerStyle(.inline)

            Picker("Sort By", selection: $options.sortKey) {
                ForEach(FileSortKey.allCases) { key in
                    Text(key.title).tag(key)
                }
            }
            .pickerStyle(.inline)

            Picker("Order", selection: $options.ascending) {
                Text(options.sortKey.orderTitle(ascending: false)).tag(false)
                Text(options.sortKey.orderTitle(ascending: true)).tag(true)
            }
            .pickerStyle(.inline)

            Picker("View", selection: $options.viewStyle) {
                ForEach(FileViewStyle.allCases) { style in
                    Label(style.title, systemImage: style.symbolName).tag(style)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "slider.horizontal.3")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Grouping, sorting and view")
    }

    // MARK: - Files content

    @ViewBuilder
    private var filesContent: some View {
        if registry.folders.isEmpty {
            noFoldersState
        } else if !store.hasAccess {
            permissionDenied
        } else {
            VStack(spacing: 0) {
                if !store.failedFolders.isEmpty { failureBanner }
                if store.files.isEmpty && options.grouping == .merged {
                    emptyState
                } else {
                    FileListView(store: store, options: options)
                }
            }
        }
    }

    private var failureBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Can't read \(store.failedFolders.map(\.name).joined(separator: ", "))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.08))
    }

    private var noFoldersState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("No folders tracked")
                .font(.headline)
            Text("Add a folder to see its files here.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Add Folder...") { registry.chooseFolder() }
                .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(registry.folders.count == 1 ? "\(registry.folders[0].name) is empty" : "Nothing here")
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
            Text("Grant access in System Settings ->\nPrivacy & Security -> Files and Folders.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button("Add Folder...") {
                    registry.chooseFolder()
                }
            }
            .padding(.top, 4)
            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
    }
}
