import Foundation

struct Site: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var url: URL
    var shortcut: Shortcut?

    init(id: UUID = UUID(), title: String, url: URL, shortcut: Shortcut? = nil) {
        self.id = id
        self.title = title
        self.url = url
        self.shortcut = shortcut
    }

    /// A tab belongs to the site when it is the saved page or anything beneath its path.
    func matches(tabURL: String) -> Bool {
        let base = Self.withoutTrailingSlash(url.absoluteString).lowercased()
        let tab = Self.withoutTrailingSlash(tabURL).lowercased()
        return tab == base || tab.hasPrefix(base + "/") || tab.hasPrefix(base + "?") || tab.hasPrefix(base + "#")
    }

    private static func withoutTrailingSlash(_ string: String) -> String {
        string.hasSuffix("/") ? String(string.dropLast()) : string
    }

    /// Accepts what people type into an address bar: "github.com" becomes https://github.com.
    static func normalizedURL(from input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let url = URL(string: withScheme),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }
}
