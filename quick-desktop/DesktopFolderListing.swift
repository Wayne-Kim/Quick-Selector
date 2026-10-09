import Foundation

/// Reads a tracked folder into the grid's model: visible files, newest mtime first.
/// Kept independent of `DesktopStore` so tests can exercise the same scan the panel uses.
enum DesktopFolderListing {
    /// Names that would only clutter a grab-from-Desktop panel.
    static func isListedFileName(_ name: String) -> Bool {
        if name.hasPrefix(".") { return false }
        if name == "Icon\r" { return false }
        return true
    }

    /// Newest `modifiedAt` first; name is the tie-breaker so equal mtimes stay stable.
    static func sortedNewestFirst(_ files: [DesktopFile]) -> [DesktopFile] {
        files.sorted { lhs, rhs in
            if lhs.modifiedAt != rhs.modifiedAt {
                return lhs.modifiedAt > rhs.modifiedAt
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    /// Directory scan used by the live store. Hidden files and packages are skipped.
    nonisolated static func load(
        at url: URL,
        fileManager: FileManager = .default
    ) -> Result<[DesktopFile], Error> {
        let keys: [URLResourceKey] = [
            .contentModificationDateKey,
            .fileSizeKey,
            .isDirectoryKey,
            .isHiddenKey,
            .nameKey,
        ]
        do {
            let urls = try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
            var items: [DesktopFile] = []
            items.reserveCapacity(urls.count)
            for fileURL in urls {
                let name = fileURL.lastPathComponent
                guard isListedFileName(name) else { continue }
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
            return .success(sortedNewestFirst(items))
        } catch {
            return .failure(error)
        }
    }
}
