import AppKit
import QuickLookThumbnailing

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

    func cached(for file: DesktopFile, size: CGSize) -> NSImage? {
        cache.object(forKey: key(for: file, size: size))
    }

    func thumbnail(for file: DesktopFile, size: CGSize, scale: CGFloat) async -> NSImage {
        let key = key(for: file, size: size)
        if let hit = cache.object(forKey: key) {
            return hit
        }

        let request = QLThumbnailGenerator.Request(
            fileAt: file.url,
            size: size,
            scale: scale,
            representationTypes: .thumbnail
        )

        let image: NSImage? = await withCheckedContinuation { continuation in
            generator.generateBestRepresentation(for: request) { rep, _ in
                continuation.resume(returning: rep?.nsImage)
            }
        }

        let final = image ?? fallbackIcon(for: file.url, size: size)
        let cost = costEstimate(for: final)
        cache.setObject(final, forKey: key, cost: cost)
        return final
    }

    private func key(for file: DesktopFile, size: CGSize) -> NSString {
        let mtime = Int64(file.modifiedAt.timeIntervalSince1970)
        return "\(file.url.path)@\(mtime)#\(Int(size.width))x\(Int(size.height))" as NSString
    }

    private func fallbackIcon(for url: URL, size: CGSize) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = size
        return icon
    }

    private func costEstimate(for image: NSImage) -> Int {
        let pixelWidth = image.representations.map(\.pixelsWide).max() ?? Int(image.size.width)
        let pixelHeight = image.representations.map(\.pixelsHigh).max() ?? Int(image.size.height)
        return max(1, pixelWidth * pixelHeight * 4)
    }
}
