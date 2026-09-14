import AppKit
import Combine

/// Owns the notes list: create / read / update / delete, clipboard copying, and
/// persistence to Application Support.
@MainActor
final class NoteStore: ObservableObject {
    /// Most recently edited first, matching the file grid's newest-first order.
    @Published private(set) var notes: [Note] = []
    /// The note currently open in the editor, if any.
    @Published private(set) var editingNoteID: UUID?
    /// Set briefly after a copy so the card can confirm it landed.
    @Published private(set) var recentlyCopiedID: UUID?
    @Published private(set) var lastError: String?

    /// Live text of the open editor. Its own observable object so a keystroke
    /// repaints the text view alone rather than the whole panel.
    let draft = NoteDraft()

    private var saveTask: Task<Void, Never>?
    private var copyResetTask: Task<Void, Never>?

    init() {
        notes = Self.load()
    }

    // MARK: - Create

    /// Adds an empty note and opens it for editing. Returns its id.
    @discardableResult
    func create() -> UUID {
        commitDraft()
        let note = Note()
        notes.insert(note, at: 0)
        draft.text = ""
        editingNoteID = note.id
        return note.id
    }

    // MARK: - Update

    /// Opens a note in the editor, loading its text into the draft.
    func beginEditing(_ id: UUID) {
        guard editingNoteID != id else { return }
        commitDraft()
        guard let note = notes.first(where: { $0.id == id }) else { return }
        draft.text = note.text
        editingNoteID = id
    }

    /// Writes the draft back to its note and leaves the editor.
    func endEditing() {
        commitDraft()
        editingNoteID = nil
    }

    /// Flushes the in-progress edit into the notes list without closing the
    /// editor. Safe to call at any time — the panel does so when it hides.
    /// A note left entirely blank is dropped rather than kept as an empty row.
    func commitDraft() {
        guard let id = editingNoteID,
              let index = notes.firstIndex(where: { $0.id == id }) else { return }
        let text = draft.text

        // Checked before the change guard: a note created and then left empty
        // never differs from its stored text, but still shouldn't be kept.
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            notes.remove(at: index)
            editingNoteID = nil
            draft.text = ""
            scheduleSave()
            return
        }

        guard notes[index].text != text else { return }
        notes[index].text = text
        notes[index].updatedAt = Date()
        notes.sort { $0.updatedAt > $1.updatedAt }
        scheduleSave()
    }

    // MARK: - Delete

    func delete(_ id: UUID) {
        if editingNoteID == id {
            editingNoteID = nil
            draft.text = ""
        }
        notes.removeAll { $0.id == id }
        scheduleSave()
    }

    // MARK: - Clipboard

    /// Puts the note's full text on the general pasteboard.
    func copyToPasteboard(_ id: UUID) {
        let text = (id == editingNoteID) ? draft.text : notes.first(where: { $0.id == id })?.text
        guard let text, !text.isEmpty else { NSSound.beep(); return }

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)

        recentlyCopiedID = id
        copyResetTask?.cancel()
        copyResetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            guard !Task.isCancelled else { return }
            self?.recentlyCopiedID = nil
        }
    }

    // MARK: - Keyboard

    /// Handles a key press while the panel is showing notes. Returns `true`
    /// when the event was consumed and should not propagate further.
    func handleKeyDown(_ event: NSEvent) -> Bool {
        let cmd = event.modifierFlags.contains(.command)

        // While the editor is open the text view owns the keyboard; only
        // Escape and ⌘Return are intercepted.
        if editingNoteID != nil {
            switch event.keyCode {
            case 53:                          // Escape -> close the editor
                endEditing()
                return true
            case 36, 76:                      // ⌘Return -> done; plain Return types
                guard cmd else { return false }
                endEditing()
                return true
            default:
                return false
            }
        }

        if cmd, event.keyCode == 45 {         // ⌘N -> new note
            create()
            return true
        }
        return false
    }

    // MARK: - Persistence

    private static var storeURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSString("~/Library/Application Support").expandingTildeInPath)
        // Kept under the old app name so notes written before the rename still load.
        let directory = base.appendingPathComponent("quick-desktop", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("notes.json")
    }

    private static func load() -> [Note] {
        guard let data = try? Data(contentsOf: storeURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode([Note].self, from: data) else { return [] }
        return decoded.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Coalesces the writes a burst of typing would otherwise produce.
    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = notes
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await self?.write(snapshot)
        }
    }

    /// Commits any open edit and writes it out immediately. Used on quit, where
    /// the debounced save would never fire.
    func flush() {
        commitDraft()
        saveTask?.cancel()
        saveTask = nil
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(notes) else { return }
        try? data.write(to: Self.storeURL, options: .atomic)
    }

    private func write(_ snapshot: [Note]) async {
        let url = Self.storeURL
        let failure: String? = await Task.detached(priority: .utility) {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            do {
                try encoder.encode(snapshot).write(to: url, options: .atomic)
                return nil
            } catch {
                return (error as NSError).localizedDescription
            }
        }.value
        if let failure { lastError = failure }
    }
}

/// The open editor's text. Separate from `NoteStore` so that typing notifies
/// only the text view — the same split the inline rename field uses.
@MainActor
final class NoteDraft: ObservableObject {
    @Published var text: String = ""
}
