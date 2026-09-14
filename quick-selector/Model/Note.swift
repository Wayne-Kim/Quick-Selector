import Foundation

/// A short text note kept alongside the tracked folder — a scratchpad for the
/// snippets you would otherwise park in an untitled TextEdit window.
struct Note: Identifiable, Hashable, Codable {
    let id: UUID
    var text: String
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), text: String = "", createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// First non-empty line, used as the card's headline.
    var title: String {
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return trimmed }
        }
        return ""
    }

    /// Everything after the title line, collapsed onto one line for the card.
    var preview: String {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        // Drop everything up to and including the title line.
        if let titleIndex = lines.firstIndex(where: { !$0.isEmpty }) {
            lines.removeFirst(titleIndex + 1)
        }
        return lines.filter { !$0.isEmpty }.joined(separator: " ")
    }

    var isBlank: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
