import Foundation
import Combine

@MainActor
final class DesktopStore: ObservableObject {
    @Published private(set) var files: [DesktopFile] = []
    @Published private(set) var hasAccess: Bool = true
    @Published private(set) var lastError: String?

    let desktopURL: URL
    private var observer: DesktopFolderObserver?

    init(desktopURL: URL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        ?? URL(fileURLWithPath: NSString("~/Desktop").expandingTildeInPath)) {
        self.desktopURL = desktopURL
        startObserving()
    }

    private func startObserving() {
        let observer = DesktopFolderObserver(url: desktopURL) { [weak self] in
            Task { @MainActor in
                self?.refresh()
            }
        }
        observer.start()
        self.observer = observer
    }

    func refresh() {
        let url = desktopURL
        Task.detached { [weak self] in
            let result = Self.loadFiles(at: url)
            await MainActor.run {
                guard let self else { return }
                switch result {
                case .success(let files):
                    self.files = files
                    self.hasAccess = true
                    self.lastError = nil
                case .failure(let error):
                    self.files = []
                    let ns = error as NSError
                    if ns.domain == NSCocoaErrorDomain && (ns.code == NSFileReadNoPermissionError || ns.code == 257) {
                        self.hasAccess = false
                    }
                    self.lastError = ns.localizedDescription
                }
            }
        }
    }

    nonisolated private static func loadFiles(at url: URL) -> Result<[DesktopFile], Error> {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [
            .contentModificationDateKey,
            .fileSizeKey,
            .isDirectoryKey,
            .isHiddenKey,
            .nameKey,
        ]
        do {
            let urls = try fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
            var items: [DesktopFile] = []
            items.reserveCapacity(urls.count)
            for fileURL in urls {
                let name = fileURL.lastPathComponent
                if name.hasPrefix(".") { continue }
                if name == "Icon\r" { continue }
                let values = try? fileURL.resourceValues(forKeys: Set(keys))
                let mtime = values?.contentModificationDate ?? .distantPast
                let size = Int64(values?.fileSize ?? 0)
                let isDir = values?.isDirectory ?? false
                items.append(DesktopFile(
                    url: fileURL,
                    name: name,
                    modifiedAt: mtime,
                    size: size,
                    isDirectory: isDir
                ))
            }
            items.sort { $0.modifiedAt > $1.modifiedAt }
            return .success(items)
        } catch {
            return .failure(error)
        }
    }
}
