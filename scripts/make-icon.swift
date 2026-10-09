// Draws the app icon (a flame in palette colors on a dark squircle) and packs it into an .icns.
// Usage: swift scripts/make-icon.swift <output.icns>
import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.icns"
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Aura-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = s * 0.1
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let squircle = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)

    NSGradient(colors: [NSColor(red: 0.13, green: 0.05, blue: 0.08, alpha: 1),
                        NSColor(red: 0.03, green: 0.02, blue: 0.05, alpha: 1)])!
        .draw(in: squircle, angle: -90)

    // Ember glow at the bottom.
    NSGraphicsContext.current?.saveGraphicsState()
    squircle.addClip()
    NSGradient(colors: [NSColor(red: 1, green: 0.35, blue: 0, alpha: 0.55), NSColor(red: 1, green: 0.2, blue: 0, alpha: 0)])!
        .draw(fromCenter: NSPoint(x: s / 2, y: rect.minY), radius: 0,
              toCenter: NSPoint(x: s / 2, y: rect.minY), radius: rect.width * 0.75, options: [])
    NSGraphicsContext.current?.restoreGraphicsState()

    // The flame: SF Symbol used as a mask for a fire gradient.
    let config = NSImage.SymbolConfiguration(pointSize: s * 0.52, weight: .regular)
    if let symbol = NSImage(systemSymbolName: "flame.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let symbolSize = symbol.size
        let origin = NSPoint(x: (s - symbolSize.width) / 2, y: (s - symbolSize.height) / 2 - s * 0.02)
        let flameRect = NSRect(origin: origin, size: symbolSize)
        let mask = NSImage(size: NSSize(width: s, height: s), flipped: false) { _ in
            NSGradient(colors: [NSColor(red: 0.85, green: 0.05, blue: 0, alpha: 1),
                                NSColor(red: 1, green: 0.42, blue: 0, alpha: 1),
                                NSColor(red: 1, green: 0.85, blue: 0.3, alpha: 1)])!
                .draw(in: flameRect.insetBy(dx: 2, dy: 2), angle: 90)
            symbol.draw(in: flameRect, from: .zero, operation: .destinationIn, fraction: 1)
            return true
        }
        mask.draw(in: NSRect(x: 0, y: 0, width: s, height: s))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try render(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", output]
try process.run()
process.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
exit(process.terminationStatus)
