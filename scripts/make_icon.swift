import AppKit

// 用法: swift scripts/make_icon.swift <输出目录> [dev|release]
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources"
let isDev = CommandLine.arguments.count > 2 && CommandLine.arguments[2] == "dev"
let size = 1024

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0
) else {
    fatalError("cannot create bitmap")
}
rep.size = NSSize(width: size, height: size)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let rect = NSRect(x: 0, y: 0, width: size, height: size)
let path = NSBezierPath(roundedRect: rect, xRadius: 230, yRadius: 230)
let gradient = NSGradient(colors: isDev
    ? [NSColor(red: 0.95, green: 0.55, blue: 0.20, alpha: 1),
       NSColor(red: 0.85, green: 0.25, blue: 0.30, alpha: 1)]
    : [NSColor(red: 0.23, green: 0.51, blue: 0.96, alpha: 1),
       NSColor(red: 0.55, green: 0.30, blue: 0.93, alpha: 1)])!
gradient.draw(in: path, angle: -55)

let config = NSImage.SymbolConfiguration(pointSize: 520, weight: .semibold)
    .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
if let mic = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    let micSize = mic.size
    let micRect = NSRect(
        x: (CGFloat(size) - micSize.width) / 2,
        y: (CGFloat(size) - micSize.height) / 2 + (isDev ? 40 : -10),
        width: micSize.width,
        height: micSize.height
    )
    mic.draw(in: micRect)
}

if isDev {
    let text = "DEV" as NSString
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 190, weight: .heavy),
        .foregroundColor: NSColor.white,
    ]
    let textSize = text.size(withAttributes: attrs)
    text.draw(at: NSPoint(x: (CGFloat(size) - textSize.width) / 2, y: 60), withAttributes: attrs)
}

NSGraphicsContext.restoreGraphicsState()

let png = rep.representation(using: .png, properties: [:])!
let pngPath = "\(outDir)/icon_1024\(isDev ? "_dev" : "").png"
try png.write(to: URL(fileURLWithPath: pngPath))
print("written: \(pngPath)")
