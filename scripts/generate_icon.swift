import AppKit

// Renders Quiver's app icon — a bold archery arrow (a "quiver" holds arrows), rendered as frosted
// glass on a blue→purple gradient squircle with a specular sheen — to a 1024×1024 PNG. The same
// arrow shape (see QuiverIcon.arrowGlyph) is reused monochrome as the menu-bar glyph.
// Usage: swift generate_icon.swift <output.png>

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon-1024.png"
let size: CGFloat = 1024

func squircle(_ r: CGRect, _ rad: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil)
}

// Gradient squircle with a soft corner sheen and a thin inner-edge highlight.
func background(_ ctx: CGContext, _ S: CGFloat) {
    let rect = CGRect(x: 0, y: 0, width: S, height: S); let rad = S * 0.225
    let cs = CGColorSpaceCreateDeviceRGB()
    ctx.saveGState(); ctx.addPath(squircle(rect, rad)); ctx.clip()
    let g = CGGradient(colorsSpace: cs, colors: [
        NSColor(srgbRed: 0.34, green: 0.58, blue: 1.0, alpha: 1).cgColor,
        NSColor(srgbRed: 0.46, green: 0.30, blue: 0.95, alpha: 1).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: S * 0.1, y: S * 0.95), end: CGPoint(x: S * 0.95, y: S * 0.05), options: [])
    let sheen = CGGradient(colorsSpace: cs, colors: [
        NSColor.white.withAlphaComponent(0.55).cgColor,
        NSColor.white.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(sheen, startCenter: CGPoint(x: S * 0.30, y: S * 0.82), startRadius: 0,
                           endCenter: CGPoint(x: S * 0.30, y: S * 0.82), endRadius: S * 0.72, options: [])
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.30).cgColor); ctx.setLineWidth(S * 0.006)
    ctx.addPath(squircle(rect.insetBy(dx: S * 0.012, dy: S * 0.012), rad * 0.95)); ctx.strokePath()
    ctx.restoreGState()
}

// Diagonal specular streak across the glass.
func sheenStreak(_ ctx: CGContext, _ S: CGFloat) {
    let rect = CGRect(x: 0, y: 0, width: S, height: S); let rad = S * 0.225
    ctx.saveGState(); ctx.addPath(squircle(rect, rad)); ctx.clip()
    let cs = CGColorSpaceCreateDeviceRGB()
    let g = CGGradient(colorsSpace: cs, colors: [
        NSColor.white.withAlphaComponent(0).cgColor,
        NSColor.white.withAlphaComponent(0.18).cgColor,
        NSColor.white.withAlphaComponent(0).cgColor] as CFArray, locations: [0.40, 0.60, 0.80])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: S), end: CGPoint(x: S, y: 0), options: [])
    ctx.restoreGState()
}

// Fills a glyph path as frosted glass: drop shadow for depth, a top→bottom gloss, and a bright crown.
func glassFill(_ ctx: CGContext, _ path: CGPath, _ S: CGFloat) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -S * 0.014), blur: S * 0.035,
                  color: NSColor(srgbRed: 0.15, green: 0.10, blue: 0.35, alpha: 0.40).cgColor)
    ctx.addPath(path); ctx.setFillColor(NSColor.white.cgColor); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState(); ctx.addPath(path); ctx.clip()
    let cs = CGColorSpaceCreateDeviceRGB(); let b = path.boundingBox
    let g = CGGradient(colorsSpace: cs, colors: [
        NSColor.white.cgColor, NSColor(white: 0.90, alpha: 1).cgColor,
        NSColor(srgbRed: 0.86, green: 0.90, blue: 1.0, alpha: 1).cgColor] as CFArray, locations: [0, 0.6, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: b.maxY), end: CGPoint(x: 0, y: b.minY), options: [])
    let gloss = CGGradient(colorsSpace: cs, colors: [
        NSColor.white.withAlphaComponent(0.9).cgColor,
        NSColor.white.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gloss, start: CGPoint(x: 0, y: b.maxY), end: CGPoint(x: 0, y: b.maxY - b.height * 0.45), options: [])
    ctx.restoreGState()
}

// A bold archery arrow — capsule shaft, triangular head, and two swept feathers at the nock. Tuned
// to stay legible when drawn small and monochrome (it doubles as the menu-bar glyph).
func arrowGlyph(_ S: CGFloat) -> CGPath {
    let cx = S / 2, sw = S * 0.105
    let yNock = S * 0.12, yTip = S * 0.88, yHeadBase = S * 0.60, hw = S * 0.205
    let p = CGMutablePath()
    p.addRoundedRect(in: CGRect(x: cx - sw / 2, y: yNock, width: sw, height: yHeadBase - yNock + S * 0.03),
                     cornerWidth: sw / 2, cornerHeight: sw / 2)
    let head = CGMutablePath()
    head.move(to: CGPoint(x: cx, y: yTip))
    head.addLine(to: CGPoint(x: cx - hw, y: yHeadBase))
    head.addLine(to: CGPoint(x: cx + hw, y: yHeadBase)); head.closeSubpath()
    p.addPath(head)
    for s in [CGFloat(-1), 1] {
        let inX = cx + s * sw * 0.30
        let f = CGMutablePath()
        f.move(to: CGPoint(x: inX, y: yNock + S * 0.33))
        f.addLine(to: CGPoint(x: cx + s * (sw * 0.30 + S * 0.165), y: yNock + S * 0.15))
        f.addLine(to: CGPoint(x: cx + s * (sw * 0.30 + S * 0.165), y: yNock - S * 0.01))
        f.addLine(to: CGPoint(x: inX, y: yNock + S * 0.07)); f.closeSubpath()
        p.addPath(f)
    }
    return p
}

func drawArrow(_ ctx: CGContext, _ S: CGFloat) {
    glassFill(ctx, arrowGlyph(S), S)
}

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { exit(1) }
background(ctx, size)
drawArrow(ctx, size)
sheenStreak(ctx, size)
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
