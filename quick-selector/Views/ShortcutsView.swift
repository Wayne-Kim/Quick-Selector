import SwiftUI

struct ShortcutsView: View {
    @ObservedObject var store: SiteStore

    var body: some View {
        if store.sites.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(store.sites) { site in
                        ShortcutRow(
                            store: store,
                            site: site,
                            isRecording: store.recordingSiteID == site.id,
                            isUnavailable: store.unavailableShortcutIDs.contains(site.id)
                        )
                    }
                }
                .padding(10)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "command")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("Add a site in the Sites tab first")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ShortcutRow: View {
    let store: SiteStore
    let site: Site
    let isRecording: Bool
    let isUnavailable: Bool

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(site.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(statusText)
                    .font(.caption2)
                    .foregroundStyle(isUnavailable ? Color.orange : Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            recordButton
            if site.shortcut != nil, !isRecording {
                Button {
                    store.clearShortcut(site.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove shortcut")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isRecording ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isRecording ? 1 : 0.5)
        )
    }

    private var statusText: String {
        if isRecording { return "Press keys - esc to cancel, delete to clear" }
        if isUnavailable { return "Used by another app" }
        return site.url.absoluteString
    }

    private var recordButton: some View {
        Button {
            isRecording ? store.cancelRecording() : store.beginRecording(site.id)
        } label: {
            Text(isRecording ? "Recording..." : (site.shortcut?.label ?? "Set Shortcut"))
                .font(.callout.monospaced())
                .frame(minWidth: 90)
        }
        .help("Record a shortcut")
    }
}
