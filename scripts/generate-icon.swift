#!/usr/bin/env swift

import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: generate-icon.swift OUTPUT.iconset\n", stderr)
    exit(2)
}

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let entries: [(filename: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

func drawSymbol(_ name: String, size: CGFloat, color: NSColor, center: NSPoint) {
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return }
    let pointSize = size * 0.82
    let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
    guard let symbol = base.withSymbolConfiguration(configuration) else { return }

    let ratio = symbol.size.width / max(symbol.size.height, 1)
    let drawSize: NSSize
    if ratio >= 1 {
        drawSize = NSSize(width: size, height: size / ratio)
    } else {
        drawSize = NSSize(width: size * ratio, height: size)
    }
    symbol.draw(
        in: NSRect(
            x: center.x - drawSize.width / 2,
            y: center.y - drawSize.height / 2,
            width: drawSize.width,
            height: drawSize.height
        ),
        from: .zero,
        operation: .sourceOver,
        fraction: 1
    )
}

for entry in entries {
    let size = entry.pixels
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { continue }

    bitmap.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

    let canvas = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.setFill()
    canvas.fill()

    let inset = CGFloat(size) * 0.055
    let tileRect = canvas.insetBy(dx: inset, dy: inset)
    let tile = NSBezierPath(
        roundedRect: tileRect,
        xRadius: CGFloat(size) * 0.23,
        yRadius: CGFloat(size) * 0.23
    )
    let gradient = NSGradient(colorsAndLocations:
        (NSColor(calibratedRed: 0.10, green: 0.15, blue: 0.34, alpha: 1), 0),
        (NSColor(calibratedRed: 0.20, green: 0.42, blue: 0.98, alpha: 1), 0.52),
        (NSColor(calibratedRed: 0.39, green: 0.22, blue: 0.89, alpha: 1), 1)
    )!
    gradient.draw(in: tile, angle: -38)

    NSGraphicsContext.saveGraphicsState()
    tile.addClip()
    let glowRect = NSRect(
        x: CGFloat(size) * 0.10,
        y: CGFloat(size) * 0.48,
        width: CGFloat(size) * 0.78,
        height: CGFloat(size) * 0.50
    )
    let glow = NSBezierPath(ovalIn: glowRect)
    NSColor.white.withAlphaComponent(0.075).setFill()
    glow.fill()

    let haloSize = CGFloat(size) * 0.53
    let haloRect = NSRect(
        x: (CGFloat(size) - haloSize) / 2,
        y: (CGFloat(size) - haloSize) / 2,
        width: haloSize,
        height: haloSize
    )
    NSColor.white.withAlphaComponent(0.10).setFill()
    NSBezierPath(ovalIn: haloRect).fill()
    NSGraphicsContext.restoreGraphicsState()

    drawSymbol(
        "video.fill",
        size: CGFloat(size) * 0.39,
        color: .white,
        center: NSPoint(x: CGFloat(size) * 0.48, y: CGFloat(size) * 0.48)
    )
    drawSymbol(
        "sparkle",
        size: CGFloat(size) * 0.18,
        color: NSColor(calibratedRed: 0.35, green: 0.97, blue: 0.77, alpha: 1),
        center: NSPoint(x: CGFloat(size) * 0.71, y: CGFloat(size) * 0.72)
    )

    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else { continue }
    try png.write(to: output.appendingPathComponent(entry.filename))
}
