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

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.setFill()
    rect.fill()

    let inset = CGFloat(size) * 0.055
    let tile = NSBezierPath(roundedRect: rect.insetBy(dx: inset, dy: inset), xRadius: CGFloat(size) * 0.22, yRadius: CGFloat(size) * 0.22)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.16, green: 0.43, blue: 0.96, alpha: 1),
        NSColor(calibratedRed: 0.39, green: 0.24, blue: 0.91, alpha: 1)
    ])!
    gradient.draw(in: tile, angle: -45)

    NSColor.white.setFill()
    let camera = NSBezierPath(
        roundedRect: NSRect(
            x: CGFloat(size) * 0.22,
            y: CGFloat(size) * 0.32,
            width: CGFloat(size) * 0.42,
            height: CGFloat(size) * 0.36
        ),
        xRadius: CGFloat(size) * 0.08,
        yRadius: CGFloat(size) * 0.08
    )
    camera.fill()

    let lens = NSBezierPath()
    lens.move(to: NSPoint(x: CGFloat(size) * 0.67, y: CGFloat(size) * 0.43))
    lens.line(to: NSPoint(x: CGFloat(size) * 0.82, y: CGFloat(size) * 0.34))
    lens.line(to: NSPoint(x: CGFloat(size) * 0.82, y: CGFloat(size) * 0.66))
    lens.line(to: NSPoint(x: CGFloat(size) * 0.67, y: CGFloat(size) * 0.57))
    lens.close()
    lens.fill()

    let plusRadius = CGFloat(size) * 0.15
    let plusCenter = NSPoint(x: CGFloat(size) * 0.72, y: CGFloat(size) * 0.74)
    NSColor(calibratedRed: 0.08, green: 0.72, blue: 0.55, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(
        x: plusCenter.x - plusRadius,
        y: plusCenter.y - plusRadius,
        width: plusRadius * 2,
        height: plusRadius * 2
    )).fill()

    NSColor.white.setStroke()
    let plus = NSBezierPath()
    plus.lineWidth = max(1, CGFloat(size) * 0.035)
    plus.lineCapStyle = .round
    plus.move(to: NSPoint(x: plusCenter.x - plusRadius * 0.48, y: plusCenter.y))
    plus.line(to: NSPoint(x: plusCenter.x + plusRadius * 0.48, y: plusCenter.y))
    plus.move(to: NSPoint(x: plusCenter.x, y: plusCenter.y - plusRadius * 0.48))
    plus.line(to: NSPoint(x: plusCenter.x, y: plusCenter.y + plusRadius * 0.48))
    plus.stroke()

    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else { continue }
    try png.write(to: output.appendingPathComponent(entry.filename))
}
