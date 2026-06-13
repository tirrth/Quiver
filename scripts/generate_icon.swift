import AppKit

// Renders Quiver's app icon (a quiver of arrows on a blue→indigo gradient) to a 1024×1024 PNG.
// Usage: swift generate_icon.swift <output.png>

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon-1024.png"
let size: CGFloat = 1024

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { exit(1) }

// Background: rounded square with a diagonal gradient.
let rect = CGRect(x: 0, y: 0, width: size, height: size)
let radius = size * 0.225
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
ctx.clip()
let bgColors = [
    NSColor(srgbRed: 0.23, green: 0.47, blue: 0.99, alpha: 1).cgColor,
    NSColor(srgbRed: 0.40, green: 0.25, blue: 0.93, alpha: 1).cgColor
] as CFArray
if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: bgColors, locations: [0, 1]) {
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])
}

// Soft highlight in the upper-left.
ctx.setFillColor(NSColor.white.withAlphaComponent(0.10).cgColor)
ctx.fillEllipse(in: CGRect(x: -size * 0.25, y: size * 0.45, width: size * 0.9, height: size * 0.9))
ctx.restoreGState()

// One arrow: shaft + head + fletching, drawn in the context's current transform, pointing up.
func drawArrow(alpha: CGFloat) {
    let white = NSColor.white.withAlphaComponent(alpha).cgColor
    ctx.setFillColor(white)

    let shaftWidth: CGFloat = 40
    ctx.addPath(CGPath(
        roundedRect: CGRect(x: -shaftWidth / 2, y: -300, width: shaftWidth, height: 470),
        cornerWidth: shaftWidth / 2, cornerHeight: shaftWidth / 2, transform: nil
    ))
    ctx.fillPath()

    // Arrowhead.
    ctx.move(to: CGPoint(x: -105, y: 150))
    ctx.addLine(to: CGPoint(x: 0, y: 300))
    ctx.addLine(to: CGPoint(x: 105, y: 150))
    ctx.closePath()
    ctx.fillPath()

    // Fletching near the nock.
    ctx.setFillColor(NSColor.white.withAlphaComponent(alpha * 0.78).cgColor)
    for sign in [CGFloat(-1), 1] {
        ctx.move(to: CGPoint(x: 0, y: -210))
        ctx.addLine(to: CGPoint(x: sign * 78, y: -300))
        ctx.addLine(to: CGPoint(x: sign * 78, y: -210))
        ctx.addLine(to: CGPoint(x: 0, y: -120))
        ctx.closePath()
        ctx.fillPath()
    }
}

// Three arrows fanned out around a pivot below center.
let fan: [(angle: CGFloat, alpha: CGFloat)] = [(-15, 0.78), (0, 1.0), (15, 0.78)]
for arrow in fan {
    ctx.saveGState()
    ctx.translateBy(x: size / 2, y: size * 0.46)
    ctx.rotate(by: arrow.angle * .pi / 180)
    drawArrow(alpha: arrow.alpha)
    ctx.restoreGState()
}

image.unlockFocus()

guard
    let tiff = image.tiffRepresentation,
    let rep = NSBitmapImageRep(data: tiff),
    let png = rep.representation(using: .png, properties: [:])
else {
    exit(1)
}

do {
    try png.write(to: URL(fileURLWithPath: outPath))
} catch {
    FileHandle.standardError.write(Data("icon write failed: \(error)\n".utf8))
    exit(1)
}
