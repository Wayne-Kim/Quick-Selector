import Combine
import Foundation

enum FileGrouping: String, CaseIterable, Identifiable {
    case merged
    case byFolder

    var id: String { rawValue }

    var title: String {
        switch self {
        case .merged: return "All together"
        case .byFolder: return "By folder"
        }
    }
}

enum FileSortKey: String, CaseIterable, Identifiable {
    case dateModified
    case name
    case size
    case kind

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dateModified: return "Date modified"
        case .name: return "Name"
        case .size: return "Size"
        case .kind: return "Kind"
        }
    }

    func orderTitle(ascending: Bool) -> String {
        switch self {
        case .dateModified: return ascending ? "Oldest first" : "Newest first"
        case .name, .kind: return ascending ? "A to Z" : "Z to A"
        case .size: return ascending ? "Smallest first" : "Largest first"
        }
    }
}

enum FileViewStyle: String, CaseIterable, Identifiable {
    case largeIcons
    case smallIcons
    case list

    var id: String { rawValue }

    var title: String {
        switch self {
        case .largeIcons: return "Large icons"
        case .smallIcons: return "Small icons"
        case .list: return "List"
        }
    }

    var symbolName: String {
        switch self {
        case .largeIcons: return "square.grid.2x2"
        case .smallIcons: return "square.grid.3x3"
        case .list: return "list.bullet"
        }
    }

    var columnCount: Int {
        switch self {
        case .largeIcons: return 3
        case .smallIcons: return 5
        case .list: return 1
        }
    }

    var thumbnailSize: CGSize {
        switch self {
        case .largeIcons: return CGSize(width: 88, height: 88)
        case .smallIcons: return CGSize(width: 44, height: 44)
        case .list: return CGSize(width: 24, height: 24)
        }
    }

    /// Roughly one visible page, used to decide how many thumbnails to
    /// generate before the panel is opened.
    var prewarmCount: Int {
        switch self {
        case .largeIcons: return 15
        case .smallIcons: return 35
        case .list: return 20
        }
    }
}

@MainActor
final class DisplayOptions: ObservableObject {
    @Published var grouping: FileGrouping {
        didSet { UserDefaults.standard.set(grouping.rawValue, forKey: Self.groupingKey) }
    }
    @Published var sortKey: FileSortKey {
        didSet { UserDefaults.standard.set(sortKey.rawValue, forKey: Self.sortKeyKey) }
    }
    @Published var ascending: Bool {
        didSet { UserDefaults.standard.set(ascending, forKey: Self.ascendingKey) }
    }
    @Published var viewStyle: FileViewStyle {
        didSet { UserDefaults.standard.set(viewStyle.rawValue, forKey: Self.viewStyleKey) }
    }

    private static let groupingKey = "displayGrouping"
    private static let sortKeyKey = "displaySortKey"
    private static let ascendingKey = "displaySortAscending"
    private static let viewStyleKey = "displayViewStyle"

    init() {
        let defaults = UserDefaults.standard
        grouping = FileGrouping(rawValue: defaults.string(forKey: Self.groupingKey) ?? "") ?? .merged
        sortKey = FileSortKey(rawValue: defaults.string(forKey: Self.sortKeyKey) ?? "") ?? .dateModified
        ascending = defaults.object(forKey: Self.ascendingKey) as? Bool ?? false
        viewStyle = FileViewStyle(rawValue: defaults.string(forKey: Self.viewStyleKey) ?? "") ?? .largeIcons
    }
}
