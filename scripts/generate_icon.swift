import AppKit

// Renders Quiver's app icon — a bold archery arrow (a "quiver" holds arrows) in a vibrant
// blue→purple gradient with a glow, on a near-black squircle — to a 1024×1024 PNG.
// Usage: swift generate_icon.swift <output.png>

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon-1024.png"
let size: CGFloat = 1024

func C(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: 1)
}

func squircle(_ rect: CGRect, _ rad: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: rad, cornerHeight: rad, transform: nil)
}

// A bold archery arrow — shaft, head, and two swept feathers — sized to fill most of the icon.
func arrowPath(_ S: CGFloat) -> CGPath {
    let cx = S / 2, sw = S * 0.13
    let yNock = S * 0.135, yTip = S * 0.90, yHeadBase = S * 0.55, hw = S * 0.25
    let p = CGMutablePath()
    p.addRoundedRect(in: CGRect(x: cx - sw / 2, y: yNock, width: sw, height: yHeadBase - yNock + S * 0.04),
                     cornerWidth: sw / 2, cornerHeight: sw / 2)
    let head = CGMutablePath()
    head.move(to: CGPoint(x: cx, y: yTip))
    head.addLine(to: CGPoint(x: cx - hw, y: yHeadBase))
    head.addLine(to: CGPoint(x: cx + hw, y: yHeadBase)); head.closeSubpath()
    p.addPath(head)
    for s in [CGFloat(-1), 1] {
        let inX = cx + s * sw * 0.32
        let f = CGMutablePath()
        f.move(to: CGPoint(x: inX, y: yNock + S * 0.40))
        f.addLine(to: CGPoint(x: cx + s * (sw * 0.32 + S * 0.20), y: yNock + S * 0.17))
        f.addLine(to: CGPoint(x: cx + s * (sw * 0.32 + S * 0.20), y: yNock - S * 0.005))
        f.addLine(to: CGPoint(x: inX, y: yNock + S * 0.08)); f.closeSubpath()
        p.addPath(f)
    }
    return p
}

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { exit(1) }
let S = size
let rect = CGRect(x: 0, y: 0, width: S, height: S)
let rad = S * 0.225
let cs = CGColorSpaceCreateDeviceRGB()

let glowColor = C(94, 108, 255)

// Near-black squircle with a soft accent glow behind the arrow.
ctx.saveGState()
ctx.addPath(squircle(rect, rad)); ctx.clip()
let bg = CGGradient(colorsSpace: cs, colors: [C(40, 40, 52).cgColor, C(10, 10, 15).cgColor] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: S * 0.2, y: S * 0.95), end: CGPoint(x: S * 0.85, y: S * 0.05), options: [])
let glow = CGGradient(colorsSpace: cs, colors: [glowColor.withAlphaComponent(0.55).cgColor, glowColor.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: S * 0.5, y: S * 0.54), startRadius: 0,
                       endCenter: CGPoint(x: S * 0.5, y: S * 0.54), endRadius: S * 0.52, options: [])
ctx.restoreGState()

let arrow = arrowPath(S)
let b = arrow.boundingBox

// Glowing halo around the arrow.
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: S * 0.055, color: glowColor.withAlphaComponent(0.95).cgColor)
ctx.addPath(arrow); ctx.setFillColor(NSColor.white.cgColor); ctx.fillPath()
ctx.restoreGState()

// Vibrant gradient fill + a top gloss.
ctx.saveGState()
ctx.addPath(arrow); ctx.clip()
let ag = CGGradient(colorsSpace: cs, colors: [C(170, 224, 255).cgColor, C(74, 141, 255).cgColor, C(150, 92, 255).cgColor] as CFArray, locations: [0, 0.5, 1])!
ctx.drawLinearGradient(ag, start: CGPoint(x: b.minX, y: b.maxY), end: CGPoint(x: b.maxX, y: b.minY), options: [])
let gloss = CGGradient(colorsSpace: cs, colors: [NSColor.white.withAlphaComponent(0.5).cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gloss, start: CGPoint(x: 0, y: b.maxY), end: CGPoint(x: 0, y: b.maxY - b.height * 0.4), options: [])
ctx.restoreGState()

// Thin inner-edge highlight for a premium glass rim.
ctx.saveGState()
ctx.addPath(squircle(rect, rad)); ctx.clip()
ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.14).cgColor); ctx.setLineWidth(S * 0.005)
ctx.addPath(squircle(rect.insetBy(dx: S * 0.012, dy: S * 0.012), rad * 0.96)); ctx.strokePath()
ctx.restoreGState()

image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let rep = NSBitmapImageRep(data: tiff),
    let png = rep.representation(using: .png, properties: [:])
else { exit(1) }

do {
    try png.write(to: URL(fileURLWithPath: outPath))
} catch {
    FileHandle.standardError.write(Data("icon write failed: \(error)\n".utf8))
    exit(1)
}
