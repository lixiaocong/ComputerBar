import AppKit
import Foundation

struct IconSpec {
    let fileName: String
    let size: Int
}

enum IconGenerationError: Error {
    case renderFailed(Int)
    case iconutilFailed(Int32)
}

let specs = [
    IconSpec(fileName: "icon_16x16.png", size: 16),
    IconSpec(fileName: "icon_16x16@2x.png", size: 32),
    IconSpec(fileName: "icon_32x32.png", size: 32),
    IconSpec(fileName: "icon_32x32@2x.png", size: 64),
    IconSpec(fileName: "icon_128x128.png", size: 128),
    IconSpec(fileName: "icon_128x128@2x.png", size: 256),
    IconSpec(fileName: "icon_256x256.png", size: 256),
    IconSpec(fileName: "icon_256x256@2x.png", size: 512),
    IconSpec(fileName: "icon_512x512.png", size: 512),
    IconSpec(fileName: "icon_512x512@2x.png", size: 1024)
]

let fileManager = FileManager.default
let projectURL = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
let resourcesURL = projectURL.appendingPathComponent("Resources", isDirectory: true)
let iconsetURL = resourcesURL.appendingPathComponent("AppIcon.iconset", isDirectory: true)
let assetCatalogURL = resourcesURL.appendingPathComponent("AppIcon.xcassets", isDirectory: true)
let appIconSetURL = assetCatalogURL.appendingPathComponent("AppIcon.appiconset", isDirectory: true)
let icnsURL = resourcesURL.appendingPathComponent("AppIcon.icns")
let previewURL = resourcesURL.appendingPathComponent("AppIcon-preview.png")

try fileManager.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
if fileManager.fileExists(atPath: iconsetURL.path) {
    try fileManager.removeItem(at: iconsetURL)
}
if fileManager.fileExists(atPath: appIconSetURL.path) {
    try fileManager.removeItem(at: appIconSetURL)
}
try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
try fileManager.createDirectory(at: appIconSetURL, withIntermediateDirectories: true)

for spec in specs {
    guard let data = renderIcon(size: spec.size) else {
        throw IconGenerationError.renderFailed(spec.size)
    }
    try data.write(to: iconsetURL.appendingPathComponent(spec.fileName))
    try data.write(to: appIconSetURL.appendingPathComponent(spec.fileName))

    if spec.size == 1024 {
        try data.write(to: previewURL)
    }
}

try appIconContentsJSON().write(
    to: appIconSetURL.appendingPathComponent("Contents.json"),
    atomically: true,
    encoding: .utf8
)

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetURL.path, "-o", icnsURL.path]
try iconutil.run()
iconutil.waitUntilExit()

if iconutil.terminationStatus == 0 {
    print("Generated \(icnsURL.path)")
} else if fileManager.fileExists(atPath: icnsURL.path) {
    print("Warning: iconutil failed; keeping existing \(icnsURL.path)")
} else {
    throw IconGenerationError.iconutilFailed(iconutil.terminationStatus)
}

func appIconContentsJSON() -> String {
    """
    {
      "images" : [
        { "filename" : "icon_16x16.png", "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
        { "filename" : "icon_16x16@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
        { "filename" : "icon_32x32.png", "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
        { "filename" : "icon_32x32@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
        { "filename" : "icon_128x128.png", "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
        { "filename" : "icon_128x128@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
        { "filename" : "icon_256x256.png", "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
        { "filename" : "icon_256x256@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
        { "filename" : "icon_512x512.png", "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
        { "filename" : "icon_512x512@2x.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
      ],
      "info" : {
        "author" : "xcode",
        "version" : 1
      }
    }
    """
}

func renderIcon(size: Int) -> Data? {
    let bitmap = NSBitmapImageRep(
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
    )

    guard let bitmap else { return nil }
    bitmap.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current = context
    context?.cgContext.interpolationQuality = .high
    context?.cgContext.setAllowsAntialiasing(true)

    let canvas = NSRect(x: 0, y: 0, width: size, height: size)
    drawBackground(in: canvas)
    drawPanel(in: canvas)
    drawServerRack(in: canvas)
    drawUsageBars(in: canvas)

    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])
}

func drawBackground(in canvas: NSRect) {
    let unit = canvas.width / 1024
    let iconRect = canvas.insetBy(dx: 60 * unit, dy: 60 * unit)
    let path = NSBezierPath(roundedRect: iconRect, xRadius: 220 * unit, yRadius: 220 * unit)

    NSGraphicsContext.saveGraphicsState()
    path.addClip()

    NSGradient(colors: [
        NSColor(srgbRed: 0.06, green: 0.10, blue: 0.16, alpha: 1),
        NSColor(srgbRed: 0.10, green: 0.17, blue: 0.26, alpha: 1)
    ])?.draw(in: path, angle: -90)

    NSColor(srgbRed: 0.10, green: 0.66, blue: 0.88, alpha: 0.20).setFill()
    NSBezierPath(ovalIn: NSRect(
        x: iconRect.minX - 150 * unit,
        y: iconRect.maxY - 430 * unit,
        width: 620 * unit,
        height: 620 * unit
    )).fill()

    NSColor(srgbRed: 0.26, green: 0.84, blue: 0.54, alpha: 0.16).setFill()
    NSBezierPath(ovalIn: NSRect(
        x: iconRect.maxX - 420 * unit,
        y: iconRect.minY - 80 * unit,
        width: 500 * unit,
        height: 500 * unit
    )).fill()

    NSGraphicsContext.restoreGraphicsState()

    NSColor.white.withAlphaComponent(0.10).setStroke()
    path.lineWidth = 6 * unit
    path.stroke()
}

func drawPanel(in canvas: NSRect) {
    let unit = canvas.width / 1024
    let rect = canvas.insetBy(dx: 160 * unit, dy: 150 * unit)
    let path = NSBezierPath(roundedRect: rect, xRadius: 130 * unit, yRadius: 130 * unit)

    NSColor(srgbRed: 0.08, green: 0.12, blue: 0.19, alpha: 0.92).setFill()
    path.fill()

    NSColor.white.withAlphaComponent(0.10).setStroke()
    path.lineWidth = 4 * unit
    path.stroke()
}

func drawServerRack(in canvas: NSRect) {
    let unit = canvas.width / 1024
    let rackRect = NSRect(
        x: canvas.midX - 140 * unit,
        y: canvas.midY - 150 * unit,
        width: 280 * unit,
        height: 360 * unit
    )
    let rackPath = NSBezierPath(roundedRect: rackRect, xRadius: 44 * unit, yRadius: 44 * unit)

    NSColor.white.withAlphaComponent(0.12).setFill()
    rackPath.fill()

    NSColor.white.withAlphaComponent(0.20).setStroke()
    rackPath.lineWidth = 4 * unit
    rackPath.stroke()

    for index in 0..<3 {
        let rowRect = NSRect(
            x: rackRect.minX + 28 * unit,
            y: rackRect.maxY - CGFloat(index + 1) * 92 * unit - 32 * unit,
            width: rackRect.width - 56 * unit,
            height: 58 * unit
        )
        let rowPath = NSBezierPath(roundedRect: rowRect, xRadius: 22 * unit, yRadius: 22 * unit)
        NSColor.white.withAlphaComponent(0.10).setFill()
        rowPath.fill()

        let indicator = NSBezierPath(ovalIn: NSRect(
            x: rowRect.minX + 20 * unit,
            y: rowRect.midY - 8 * unit,
            width: 16 * unit,
            height: 16 * unit
        ))
        NSColor(srgbRed: 0.31, green: 0.85, blue: 0.54, alpha: 1).setFill()
        indicator.fill()

        let lineRect = NSRect(
            x: rowRect.minX + 52 * unit,
            y: rowRect.midY - 6 * unit,
            width: rowRect.width - 76 * unit,
            height: 12 * unit
        )
        let linePath = NSBezierPath(roundedRect: lineRect, xRadius: 6 * unit, yRadius: 6 * unit)
        NSColor.white.withAlphaComponent(0.22).setFill()
        linePath.fill()
    }
}

func drawUsageBars(in canvas: NSRect) {
    let unit = canvas.width / 1024
    let bottomY = canvas.minY + 220 * unit
    let barWidth = 110 * unit
    let spacing = 40 * unit
    let totalWidth = barWidth * 2 + spacing
    let startX = canvas.midX - totalWidth / 2

    drawBar(
        in: NSRect(x: startX, y: bottomY, width: barWidth, height: 220 * unit),
        fillFraction: 0.72,
        colors: (
            NSColor(srgbRed: 0.22, green: 0.76, blue: 0.98, alpha: 1),
            NSColor(srgbRed: 0.15, green: 0.56, blue: 0.97, alpha: 1)
        ),
        unit: unit
    )
    drawBar(
        in: NSRect(x: startX + barWidth + spacing, y: bottomY, width: barWidth, height: 220 * unit),
        fillFraction: 0.56,
        colors: (
            NSColor(srgbRed: 0.46, green: 0.90, blue: 0.58, alpha: 1),
            NSColor(srgbRed: 0.20, green: 0.76, blue: 0.42, alpha: 1)
        ),
        unit: unit
    )
}

func drawBar(in rect: NSRect, fillFraction: CGFloat, colors: (NSColor, NSColor), unit: CGFloat) {
    let trackPath = NSBezierPath(roundedRect: rect, xRadius: 36 * unit, yRadius: 36 * unit)
    NSColor.white.withAlphaComponent(0.10).setFill()
    trackPath.fill()

    let inset = 12 * unit
    let fillHeight = max(44 * unit, (rect.height - inset * 2) * fillFraction)
    let fillRect = NSRect(
        x: rect.minX + inset,
        y: rect.minY + inset,
        width: rect.width - inset * 2,
        height: fillHeight
    )
    let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: 24 * unit, yRadius: 24 * unit)
    NSGradient(colors: [colors.1, colors.0])?.draw(in: fillPath, angle: 90)

    NSColor.white.withAlphaComponent(0.14).setStroke()
    trackPath.lineWidth = 4 * unit
    trackPath.stroke()
}
