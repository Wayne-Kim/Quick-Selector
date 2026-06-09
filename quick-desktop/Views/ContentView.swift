import SwiftUI

struct ContentView: View {
    @ObservedObject var store: DesktopStore

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            body(for: store)
        }
        .frame(width: 360, height: 420)
    }

    private var header: some View {
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
                    FileGridItem(store: store, file: file)
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
