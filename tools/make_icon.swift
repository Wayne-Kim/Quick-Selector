#!/usr/bin/env swift
import AppKit

let outputPath = CommandLine.arguments.dropFirst().first
    ?? "quick-desktop/Assets.xcassets/AppIcon.appiconset/icon_1024.png"

let size: CGFloat = 1024
let cornerRadius: CGFloat = size * 0.2237

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let context = NSGraphicsContext.current!.cgContext

let bgPath = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: size, height: size),
                          xRadius: cornerRadius, yRadius: cornerRadius)
bgPath.addClip()

let colors = [
    NSColor(srgbRed: 0.42, green: 0.36, blue: 0.93, alpha: 1).cgColor,
    NSColor(srgbRed: 0.27, green: 0.55, blue: 0.95, alpha: 1).cgColor,
]
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: colors as CFArray, locations: [0, 1])!
context.drawLinearGradient(gradient,
                           start: CGPoint(x: 0, y: size),
                           end: CGPoint(x: size, y: 0),
                           options: [])

let symbolConfig = NSImage.SymbolConfiguration(pointSize: size * 0.58, weight: .semibold)
    .applying(.init(paletteColors: [.white]))
if let symbol = NSImage(systemSymbolName: "square.stack.3d.up.fill",
                       accessibilityDescription: nil)?
    .withSymbolConfiguration(symbolConfig) {
    let symbolSize = symbol.size
    let drawRect = NSRect(
        x: (size - symbolSize.width) / 2,
        y: (size - symbolSize.height) / 2 - size * 0.02,
        width: symbolSize.width,
        height: symbolSize.height
    )
    symbol.draw(in: drawRect)
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("failed to encode PNG\n".data(using: .utf8)!)
    exit(1)
}
try png.write(to: URL(fileURLWithPath: outputPath))
print("wrote \(outputPath)")
