import Combine
import Foundation

/// Which half of the panel is showing. Lives outside the two stores because
/// both the view and the panel's key monitor need to agree on it.
enum PanelMode: String, CaseIterable, Identifiable {
    case files
    case notes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .files: return "Files"
        case .notes: return "Notes"
        }
    }
}

@MainActor
final class PanelState: ObservableObject {
    @Published var mode: PanelMode = .files
}
