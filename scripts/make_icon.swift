// Uygulama simgesini üretir: swift scripts/make_icon.swift <çıktı.png>
import AppKit

let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let inset: CGFloat = 100
let body = NSRect(x: inset, y: inset, width: CGFloat(size) - 2 * inset, height: CGFloat(size) - 2 * inset)
let bg = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
NSGradient(colors: [NSColor(white: 0.17, alpha: 1), NSColor(white: 0.07, alpha: 1)])!.draw(in: bg, angle: -90)

// Treemap blokları (x, y, w, h — 0..1) ve ton
let blocks: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = [
    (0.00, 0.42, 0.56, 0.58, 0.58),
    (0.58, 0.62, 0.42, 0.38, 0.08),
    (0.58, 0.42, 0.20, 0.18, 0.38),
    (0.80, 0.42, 0.20, 0.18, 0.78),
    (0.00, 0.00, 0.30, 0.40, 0.97),
    (0.32, 0.18, 0.34, 0.22, 0.14),
    (0.32, 0.00, 0.34, 0.16, 0.48),
    (0.68, 0.00, 0.32, 0.40, 0.68),
]
let area = body.insetBy(dx: 92, dy: 92)
let gap: CGFloat = 12
for (x, y, w, h, hue) in blocks {
    let r = NSRect(x: area.minX + x * area.width + gap / 2, y: area.minY + y * area.height + gap / 2,
                   width: w * area.width - gap, height: h * area.height - gap)
    let p = NSBezierPath(roundedRect: r, xRadius: 26, yRadius: 26)
    NSGradient(colors: [NSColor(hue: hue, saturation: 0.55, brightness: 0.98, alpha: 1),
                        NSColor(hue: hue, saturation: 0.68, brightness: 0.82, alpha: 1)])!.draw(in: p, angle: -90)
}
NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
