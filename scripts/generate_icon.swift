import AppKit

// Renders Quiver's app icon — a faceted gem (brilliant-cut, light-catching facets) with a glow on a
// near-black squircle — to a 1024×1024 PNG. The same gem silhouette is reused as the menu-bar glyph.
// Usage: swift generate_icon.swift <output.png>

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon-1024.png"
let size: CGFloat = 1024

func C(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor { NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: 1) }
func squircle(_ rect: CGRect, _ rad: CGFloat) -> CGPath { CGPath(roundedRect: rect, cornerWidth: rad, cornerHeight: rad, transform: nil) }

/// Gem vertices in an SxS box (y-up): table at top, point at bottom.
func gemPoints(_ S: CGFloat) -> [String: CGPoint] {
    let cx = S * 0.5
    return [
        "A": CGPoint(x: cx - S * 0.20, y: S * 0.72), "B": CGPoint(x: cx + S * 0.20, y: S * 0.72),
        "C": CGPoint(x: cx + S * 0.31, y: S * 0.52), "E": CGPoint(x: cx - S * 0.31, y: S * 0.52),
        "D": CGPoint(x: cx, y: S * 0.22),
        "F": CGPoint(x: cx - S * 0.105, y: S * 0.52), "G": CGPoint(x: cx + S * 0.105, y: S * 0.52)
    ]
}

func gemOutline(_ S: CGFloat) -> CGPath {
    let p = gemPoints(S)
    let path = CGMutablePath()
    path.addLines(between: [p["A"]!, p["B"]!, p["C"]!, p["D"]!, p["E"]!])
    path.closeSubpath()
    return path
}

func facet(_ ctx: CGContext, _ ps: [CGPoint], _ col: NSColor) {
    ctx.setFillColor(col.cgColor)
    ctx.move(to: ps[0]); for p in ps.dropFirst() { ctx.addLine(to: p) }; ctx.closePath(); ctx.fillPath()
}

func drawGemFacets(_ ctx: CGContext, _ S: CGFloat) {
    let p = gemPoints(S)
    facet(ctx, [p["A"]!, p["B"]!, p["G"]!, p["F"]!], C(198, 240, 255))   // table (brightest)
    facet(ctx, [p["A"]!, p["F"]!, p["E"]!], C(140, 214, 255))           // crown left
    facet(ctx, [p["B"]!, p["C"]!, p["G"]!], C(96, 190, 240))            // crown right
    facet(ctx, [p["E"]!, p["F"]!, p["D"]!], C(58, 150, 220))            // pavilion left
    facet(ctx, [p["F"]!, p["G"]!, p["D"]!], C(40, 122, 200))            // pavilion centre (deepest)
    facet(ctx, [p["G"]!, p["C"]!, p["D"]!], C(64, 160, 225))            // pavilion right
    ctx.setStrokeColor(NSColor(white: 1, alpha: 0.18).cgColor)
    ctx.setLineWidth(S * 0.006)
    for seg in [["A", "F"], ["B", "G"], ["F", "G"], ["E", "F"], ["G", "C"], ["F", "D"], ["G", "D"]] {
        ctx.move(to: p[seg[0]]!); ctx.addLine(to: p[seg[1]]!)
    }
    ctx.strokePath()
}

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { exit(1) }
let S = size
let cs = CGColorSpaceCreateDeviceRGB()

// Near-black squircle with a soft accent glow behind the gem.
ctx.saveGState()
ctx.addPath(squircle(CGRect(x: 0, y: 0, width: S, height: S), S * 0.225)); ctx.clip()
let bg = CGGradient(colorsSpace: cs, colors: [C(28, 32, 44).cgColor, C(8, 10, 16).cgColor] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: S * 0.2, y: S * 0.95), end: CGPoint(x: S * 0.85, y: S * 0.05), options: [])
let glow = CGGradient(colorsSpace: cs, colors: [C(60, 170, 235).withAlphaComponent(0.5).cgColor, C(60, 170, 235).withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: S * 0.5, y: S * 0.5), startRadius: 0,
                       endCenter: CGPoint(x: S * 0.5, y: S * 0.5), endRadius: S * 0.5, options: [])
ctx.restoreGState()

// Glow halo around the gem.
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: S * 0.05, color: C(80, 190, 255).withAlphaComponent(0.9).cgColor)
ctx.addPath(gemOutline(S)); ctx.setFillColor(NSColor.white.cgColor); ctx.fillPath()
ctx.restoreGState()

drawGemFacets(ctx, S)

// Top sheen across the gem.
ctx.saveGState()
ctx.addPath(gemOutline(S)); ctx.clip()
let b = gemOutline(S).boundingBox
let gloss = CGGradient(colorsSpace: cs, colors: [NSColor.white.withAlphaComponent(0.45).cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gloss, start: CGPoint(x: 0, y: b.maxY), end: CGPoint(x: 0, y: b.maxY - b.height * 0.35), options: [])
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
