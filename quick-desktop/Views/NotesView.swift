import SwiftUI

/// The notes half of the panel: a list of note cards, or the editor when one
/// is open. Styled to match the file grid — same corner radii, same hover
/// treatment, same newest-first ordering.
struct NotesView: View {
    @ObservedObject var store: NoteStore

    var body: some View {
        if let id = store.editingNoteID {
            NoteEditorView(
                store: store,
                draft: store.draft,
                noteID: id,
                isCopied: store.recentlyCopiedID == id
            )
        } else if store.notes.isEmpty {
            emptyState
        } else {
            list
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(store.notes) { note in
                    NoteCard(
                        store: store,
                        note: note,
                        isCopied: store.recentlyCopiedID == note.id
                    )
                    .equatable()
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "note.text")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("No notes yet")
                .foregroundStyle(.secondary)
            Button("New Note") { store.create() }
                .padding(.top, 2)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Card

/// One row in the notes list. Takes plain values and compares equal so that a
/// change to one note doesn't repaint the rest — the same approach the file
/// cells use.
struct NoteCard: View, Equatable {
    let store: NoteStore
    let note: Note
    let isCopied: Bool

    static func == (lhs: NoteCard, rhs: NoteCard) -> Bool {
        lhs.store === rhs.store && lhs.note == rhs.note && lhs.isCopied == rhs.isCopied
    }

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(note.title.isEmpty ? .secondary : .primary)
                if !note.preview.isEmpty {
                    Text(note.preview)
                        .font(.caption2)
                        .lineLimit(2)
                        .foregroundStyle(.secondary)
                }
                Text(Self.relativeDate(note.updatedAt))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            copyButton
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovering ? Color.primary.opacity(0.08) : Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture { store.beginEditing(note.id) }
        .contextMenu {
            Button("Edit") { store.beginEditing(note.id) }
            Button("Copy Text") { store.copyToPasteboard(note.id) }
            Divider()
            Button("Delete", role: .destructive) { store.delete(note.id) }
        }
    }

    /// Mirrors the grid's star badge: revealed on hover, and pinned visible
    /// while it is confirming a copy.
    @ViewBuilder
    private var copyButton: some View {
        if isHovering || isCopied {
            Button {
                store.copyToPasteboard(note.id)
            } label: {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isCopied ? Color.green : Color.secondary)
                    .padding(4)
                    .background(.regularMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .help(isCopied ? "Copied" : "Copy text")
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private static func relativeDate(_ date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Editor

/// Full-panel editor for one note. Binds to `NoteDraft` so each keystroke
/// invalidates the text view and nothing else.
struct NoteEditorView: View {
    let store: NoteStore
    @ObservedObject var draft: NoteDraft
    let noteID: UUID
    /// Passed in rather than read off the store: this view doesn't observe the
    /// store, so it needs the flag as a value to re-render on.
    let isCopied: Bool

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            TextEditor(text: $draft.text)
                .font(.callout)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .focused($isFocused)
        }
        .onAppear { focusEditor() }
        .onDisappear { store.commitDraft() }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button {
                store.endEditing()
            } label: {
                Label("Notes", systemImage: "chevron.left")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Back to notes (esc)")
            Spacer()
            Button {
                store.copyToPasteboard(noteID)
            } label: {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(isCopied ? Color.green : Color.secondary)
            }
            .buttonStyle(.borderless)
            .help("Copy text")
            Button {
                store.delete(noteID)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete note")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// Same deferred focus the rename field needs: asserting `@FocusState`
    /// synchronously in `onAppear` lands before the field is in the panel's
    /// responder chain.
    private func focusEditor() {
        DispatchQueue.main.async { isFocused = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            if store.editingNoteID == noteID { isFocused = true }
        }
    }
}
