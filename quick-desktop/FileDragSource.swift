import AppKit
import UniformTypeIdentifiers

enum FileDragSourceError: Error {
    case noFileURL
}

/// Builds the `NSItemProvider` a grid cell uses to drag a real on-disk file
/// into another app. Drop targets (Finder, Slack, GitHub) must receive a
/// file URL, never a bare filename string or an empty provider.
enum FileDragSource {
    static var fileURLTypeIdentifier: String { UTType.fileURL.identifier }

    static func itemProvider(for fileURL: URL) -> NSItemProvider {
        let url = fileURL.standardizedFileURL
        if let provider = NSItemProvider(contentsOf: url) {
            if provider.suggestedName == nil {
                provider.suggestedName = url.lastPathComponent
            }
            return provider
        }
        return makeFallbackProvider(for: url)
    }

    /// Resolves the file URL a drop target would receive. Tests use this
    /// against the same provider the cell puts on the pasteboard.
    static func loadFileURL(from provider: NSItemProvider) async throws -> URL {
        if provider.canLoadObject(ofClass: NSURL.self) {
            let object = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<NSURL?, Error>) in
                _ = provider.loadObject(ofClass: NSURL.self) { object, error in
                    if let error {
                        cont.resume(throwing: error)
                    } else {
                        cont.resume(returning: object as? NSURL)
                    }
                }
            }
            if let object {
                return (object as URL).standardizedFileURL
            }
        }

        if provider.hasItemConformingToTypeIdentifier(fileURLTypeIdentifier) {
            let item = try await loadItem(from: provider, typeIdentifier: fileURLTypeIdentifier)
            if let url = fileURL(from: item) {
                return url
            }
        }

        if let type = provider.registeredTypeIdentifiers.first(where: { $0 != fileURLTypeIdentifier })
            ?? provider.registeredTypeIdentifiers.first {
            return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
                provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                    if let error {
                        cont.resume(throwing: error)
                        return
                    }
                    guard let url else {
                        cont.resume(throwing: FileDragSourceError.noFileURL)
                        return
                    }
                    cont.resume(returning: url.standardizedFileURL)
                }
            }
        }

        throw FileDragSourceError.noFileURL
    }

    private static func makeFallbackProvider(for url: URL) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.suggestedName = url.lastPathComponent
        let contentType = UTType(filenameExtension: url.pathExtension) ?? .data

        provider.registerFileRepresentation(
            forTypeIdentifier: contentType.identifier,
            fileOptions: [.openInPlace],
            visibility: .all
        ) { completion in
            completion(url, true, nil)
            return nil
        }

        provider.registerDataRepresentation(
            forTypeIdentifier: fileURLTypeIdentifier,
            visibility: .all
        ) { completion in
            completion(url.dataRepresentation, nil)
            return nil
        }

        return provider
    }

    private static func loadItem(
        from provider: NSItemProvider,
        typeIdentifier: String
    ) async throws -> NSSecureCoding? {
        try await withCheckedThrowingContinuation { cont in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume(returning: item)
                }
            }
        }
    }

    private static func fileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL, url.isFileURL {
            return url.standardizedFileURL
        }
        if let url = item as? NSURL {
            let resolved = url as URL
            return resolved.isFileURL ? resolved.standardizedFileURL : nil
        }
        if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL {
            return url.standardizedFileURL
        }
        if let string = item as? String, let url = URL(string: string), url.isFileURL {
            return url.standardizedFileURL
        }
        return nil
    }
}
