import AppKit

// Claude-style sunburst mark (cream rays on the brand clay squircle).
let clay  = NSColor(srgbRed: 0.851, green: 0.459, blue: 0.337, alpha: 1) // #D9754C
let cream = NSColor(srgbRed: 0.965, green: 0.949, blue: 0.925, alpha: 1) // #F6F2EC

func makeIcon(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)!

    NSColor.clear.set()
    NSRect(x: 0, y: 0, width: s, height: s).fill()

    // Rounded-rect (squircle-ish) background with a small transparent margin.
    let margin = s * 0.06
    let bg = NSRect(x: margin, y: margin, width: s - 2 * margin, height: s - 2 * margin)
    let radius = (s - 2 * margin) * 0.2237
    clay.set()
    NSBezierPath(roundedRect: bg, xRadius: radius, yRadius: radius).fill()

    // Radiating tapered rays.
    let cx = s / 2, cy = s / 2
    let count = 12
    let outerR = s * 0.325, midR = s * 0.175, innerR = s * 0.045, halfW = s * 0.052
    cream.set()
    for i in 0..<count {
        let a  = CGFloat(i) / CGFloat(count) * 2 * .pi
        let pa = a + .pi / 2
        func pt(_ r: CGFloat, _ off: CGFloat) -> NSPoint {
            NSPoint(x: cx + r * cos(a) + off * cos(pa),
                    y: cy + r * sin(a) + off * sin(pa))
        }
        let ray = NSBezierPath()
        ray.move(to: pt(innerR, 0))
        ray.line(to: pt(midR,  halfW))
        ray.line(to: pt(outerR, 0))
        ray.line(to: pt(midR, -halfW))
        ray.close()
        ray.fill()
    }
    // Solid center disc tying the rays together.
    let d = s * 0.165
    NSBezierPath(ovalIn: NSRect(x: cx - d / 2, y: cy - d / 2, width: d, height: d)).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
let dir = CommandLine.arguments[1]
for (name, px) in sizes {
    try! makeIcon(px).write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
}
print("icons -> \(dir)")
