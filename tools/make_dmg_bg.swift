import AppKit

// DMG install window background: title + "drag to Applications" arrow.
let clay  = NSColor(srgbRed: 0.851, green: 0.459, blue: 0.337, alpha: 1)
let cream = NSColor(srgbRed: 0.969, green: 0.957, blue: 0.937, alpha: 1)
let ink   = NSColor(srgbRed: 0.20,  green: 0.17,  blue: 0.15,  alpha: 1)
let gray  = NSColor(srgbRed: 0.45,  green: 0.42,  blue: 0.40,  alpha: 1)

let W: CGFloat = 660, H: CGFloat = 420

func centered(_ text: String, font: NSFont, color: NSColor, topY: CGFloat) {
    let para = NSMutableParagraphStyle(); para.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font, .foregroundColor: color, .paragraphStyle: para
    ]
    let str = NSAttributedString(string: text, attributes: attrs)
    let h = font.ascender - font.descender + 4
    // topY is measured from the top; convert to AppKit bottom-left origin.
    let rect = NSRect(x: 0, y: H - topY - h, width: W, height: h)
    str.draw(in: rect)
}

func makeBG(scale: CGFloat) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: W, height: H)
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    ctx.cgContext.scaleBy(x: scale, y: scale)

    cream.set()
    NSRect(x: 0, y: 0, width: W, height: H).fill()

    // Titles (top-origin Y).
    centered("Claude Usage", font: .systemFont(ofSize: 30, weight: .bold), color: clay, topY: 44)
    centered("아래 앱을 Applications 폴더로 드래그하세요",
             font: .systemFont(ofSize: 15, weight: .medium), color: gray, topY: 92)

    // Arrow between the two icons (icon centers at top-Y 215).
    let yb = H - 215                 // bottom-origin center line
    let x0: CGFloat = 272, x1: CGFloat = 372
    clay.set()
    let shaft = NSBezierPath()
    shaft.lineWidth = 13
    shaft.lineCapStyle = .round
    shaft.move(to: NSPoint(x: x0, y: yb))
    shaft.line(to: NSPoint(x: x1, y: yb))
    shaft.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: x1 + 26, y: yb))
    head.line(to: NSPoint(x: x1 - 4, y: yb + 20))
    head.line(to: NSPoint(x: x1 - 4, y: yb - 20))
    head.close()
    head.fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let outDir = CommandLine.arguments[1]
try! makeBG(scale: 1).write(to: URL(fileURLWithPath: "\(outDir)/bg_1x.png"))
try! makeBG(scale: 2).write(to: URL(fileURLWithPath: "\(outDir)/bg_2x.png"))
print("dmg background -> \(outDir)")
