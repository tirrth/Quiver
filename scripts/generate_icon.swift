import AppKit

// Renders Quiver's app icon — three sliders (a "controls hub", matching the menu-bar glyph) on a
// blue→indigo gradient — to a 1024×1024 PNG. Usage: swift generate_icon.swift <output.png>

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon-1024.png"
let size: CGFloat = 1024

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { exit(1) }

// Background: rounded square with a diagonal gradient + soft sheen.
let rect = CGRect(x: 0, y: 0, width: size, height: size)
let radius = size * 0.225
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
ctx.clip()
let bgColors = [
    NSColor(srgbRed: 0.26, green: 0.52, blue: 1.00, alpha: 1).cgColor,
    NSColor(srgbRed: 0.40, green: 0.30, blue: 0.95, alpha: 1).cgColor
] as CFArray
if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: bgColors, locations: [0, 1]) {
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])
}
ctx.setFillColor(NSColor.white.withAlphaComponent(0.10).cgColor)
ctx.fillEllipse(in: CGRect(x: -size * 0.22, y: size * 0.46, width: size * 0.95, height: size * 0.95))
ctx.restoreGState()

// Three sliders.
let trackWidth = size * 0.52
let trackX = (size - trackWidth) / 2
let lineWidth = size * 0.05
let knobRadius = size * 0.058
ctx.setLineCap(.round)

// (yFraction, knobFraction-along-track)
let rows: [(CGFloat, CGFloat)] = [(0.355, 0.66), (0.5, 0.30), (0.645, 0.56)]
for (yf, kf) in rows {
    let y = size * yf

    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.42).cgColor)
    ctx.setLineWidth(lineWidth)
    ctx.move(to: CGPoint(x: trackX, y: y))
    ctx.addLine(to: CGPoint(x: trackX + trackWidth, y: y))
    ctx.strokePath()

    let kx = trackX + trackWidth * kf
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.006), blur: size * 0.03,
                  color: NSColor.black.withAlphaComponent(0.28).cgColor)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillEllipse(in: CGRect(x: kx - knobRadius, y: y - knobRadius, width: knobRadius * 2, height: knobRadius * 2))
    ctx.restoreGState()
}

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
