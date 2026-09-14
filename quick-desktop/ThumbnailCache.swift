import AppKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 400
        c.totalCostLimit = 50 * 1024 * 1024
        return c
    }()

    private let generator = QLThumbnailGenerator.shared

    /// Generations already running, keyed like `cache`, so a prewarm and the
    /// cell that scrolls into view a moment later share one QuickLook request
    /// instead of racing to produce the same image twice.
    private var inFlight: [NSString: Task<Void, Never>] = [:]

    /// Generic icons keyed by file type. One `NSWorkspace` lookup per distinct
    /// type, then reused by every cell of that type.
    private var typeIcons: [String: NSImage] = [:]

    func cached(for file: DesktopFile, size: CGSize) -> NSImage? {
        cache.object(forKey: key(for: file, size: size))
    }

    /// The stand-in shown until the real thumbnail arrives. Cheap enough to
    /// call while building a view: no disk access, no QuickLook round trip.
    func placeholder(for file: DesktopFile) -> NSImage {
        let typeKey = file.isDirectory ? "public.folder" : file.url.pathExtension.lowercased()
        if let hit = typeIcons[typeKey] { return hit }
        let type = file.isDirectory ? UTType.folder : (UTType(filenameExtension: typeKey) ?? .data)
        let icon = NSWorkspace.shared.icon(for: type)
        typeIcons[typeKey] = icon
        return icon
    }

    func thumbnail(for file: DesktopFile, size: CGSize, scale: CGFloat) async -> NSImage {
        let key = key(for: file, size: size)
        if let hit = cache.object(forKey: key) {
            return hit
        }

        if let running = inFlight[key] {
            await running.value
        } else {
            let task = Task { @MainActor in
                let request = QLThumbnailGenerator.Request(
                    fileAt: file.url,
                    size: size,
                    scale: scale,
                    representationTypes: .thumbnail
                )
                let image: NSImage? = await withCheckedContinuation { continuation in
                    self.generator.generateBestRepresentation(for: request) { rep, _ in
                        continuation.resume(returning: rep?.nsImage)
                    }
                }
                let final = image ?? self.placeholder(for: file)
                self.cache.setObject(final, forKey: key, cost: self.costEstimate(for: final))
                self.inFlight[key] = nil
            }
            inFlight[key] = task
            await task.value
        }
        return cache.object(forKey: key) ?? placeholder(for: file)
    }

    /// Starts generating thumbnails the grid is about to need, so the panel
    /// opens with images already in the cache instead of empty tiles.
    func prewarm(_ files: some Sequence<DesktopFile>, size: CGSize, scale: CGFloat) {
        for file in files {
            let key = key(for: file, size: size)
            guard cache.object(forKey: key) == nil, inFlight[key] == nil else { continue }
            Task { _ = await thumbnail(for: file, size: size, scale: scale) }
        }
    }

    private func key(for file: DesktopFile, size: CGSize) -> NSString {
        let mtime = Int64(file.modifiedAt.timeIntervalSince1970)
        return "\(file.url.path)@\(mtime)#\(Int(size.width))x\(Int(size.height))" as NSString
    }

    private func costEstimate(for image: NSImage) -> Int {
        let pixelWidth = image.representations.map(\.pixelsWide).max() ?? Int(image.size.width)
        let pixelHeight = image.representations.map(\.pixelsHigh).max() ?? Int(image.size.height)
        return max(1, pixelWidth * pixelHeight * 4)
    }
}
