import SwiftUI

struct SitesView: View {
    @ObservedObject var store: SiteStore

    @State private var address = ""
    @State private var title = ""
    @State private var isInvalid = false

    var body: some View {
        VStack(spacing: 0) {
            addForm
            Divider()
            if store.sites.isEmpty {
                emptyState
            } else {
                list
            }
        }
    }

    private var addForm: some View {
        VStack(spacing: 6) {
            TextField("URL (e.g. github.com)", text: $address)
                .onChange(of: address) { _ in isInvalid = false }
            HStack(spacing: 6) {
                TextField("Name (optional)", text: $title)
                Button("Add", action: submit)
                    .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if isInvalid {
                Text("Enter a valid web address.")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .textFieldStyle(.roundedBorder)
        .onSubmit(submit)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func submit() {
        guard store.add(address: address, title: title) else {
            isInvalid = true
            return
        }
        address = ""
        title = ""
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(store.sites) { site in
                    SiteRow(store: store, site: site)
                }
            }
            .padding(10)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "globe")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("No sites yet")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SiteRow: View {
    let store: SiteStore
    let site: Site

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "globe")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(site.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(site.url.absoluteString)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            if isHovering {
                Button {
                    store.delete(site.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Delete site")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(isHovering ? 0.08 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture { store.open(site) }
        .help("Open in Chrome")
        .contextMenu {
            Button("Open in Chrome") { store.open(site) }
            Button("Copy URL") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(site.url.absoluteString, forType: .string)
            }
            Divider()
            Button("Delete", role: .destructive) { store.delete(site.id) }
        }
    }
}
