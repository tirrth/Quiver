import SwiftUI

/// Quiver's faceted-gem brand mark, drawn to match the app and menu-bar icons. Each facet is shaded
/// (bright table down to a deep pavilion) so it reads as a real cut gem with depth — not a flat blob.
/// A soft contact shadow and a crisp defining rim keep it looking good on any background, including
/// the translucent menu material where a flat fill would wash out. Use it for in-app chrome (the hub
/// header, the About card) to keep the brand consistent with the app icon.
struct GemMark: View {
    var size: CGFloat = 22

    // Gem vertices in a unit square (SwiftUI coordinates, y-down): table across the top, point at the
    // bottom. Mirrors the geometry used by the app-icon generator and the menu-bar glyph.
    private static let vertices: [String: CGPoint] = [
        "A": CGPoint(x: 0.30, y: 0.28), "B": CGPoint(x: 0.70, y: 0.28),
        "C": CGPoint(x: 0.81, y: 0.48), "E": CGPoint(x: 0.19, y: 0.48),
        "D": CGPoint(x: 0.50, y: 0.78),
        "F": CGPoint(x: 0.395, y: 0.48), "G": CGPoint(x: 0.605, y: 0.48)
    ]

    private func point(_ key: String, _ s: CGFloat) -> CGPoint {
        let v = Self.vertices[key]!
        return CGPoint(x: v.x * s, y: v.y * s)
    }

    private func facet(_ keys: [String], _ s: CGFloat) -> Path {
        var path = Path()
        path.move(to: point(keys[0], s))
        for key in keys.dropFirst() { path.addLine(to: point(key, s)) }
        path.closeSubpath()
        return path
    }

    private func outline(_ s: CGFloat) -> Path { facet(["A", "B", "C", "D", "E"], s) }

    private static func shade(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(red: r / 255, green: g / 255, blue: b / 255)
    }

    var body: some View {
        Canvas { ctx, _ in
            let s = size

            // Soft contact shadow so the gem lifts off any background.
            ctx.drawLayer { layer in
                layer.addFilter(.shadow(color: .black.opacity(0.28), radius: s * 0.05, x: 0, y: s * 0.03))
                layer.fill(outline(s), with: .color(Self.shade(58, 150, 220)))
            }

            // Brilliant cut: brightest at the table, darkest at the pavilion centre.
            ctx.fill(facet(["A", "B", "G", "F"], s), with: .color(Self.shade(190, 232, 255)))  // table
            ctx.fill(facet(["A", "F", "E"], s),      with: .color(Self.shade(132, 206, 250)))  // crown left
            ctx.fill(facet(["B", "C", "G"], s),      with: .color(Self.shade(92, 184, 236)))   // crown right
            ctx.fill(facet(["E", "F", "D"], s),      with: .color(Self.shade(54, 144, 214)))   // pavilion left
            ctx.fill(facet(["F", "G", "D"], s),      with: .color(Self.shade(38, 118, 196)))   // pavilion centre
            ctx.fill(facet(["G", "C", "D"], s),      with: .color(Self.shade(60, 156, 222)))   // pavilion right

            var edges = Path()
            for segment in [["A", "F"], ["B", "G"], ["F", "G"], ["E", "F"], ["G", "C"], ["F", "D"], ["G", "D"]] {
                edges.move(to: point(segment[0], s))
                edges.addLine(to: point(segment[1], s))
            }
            ctx.stroke(edges, with: .color(.white.opacity(0.28)), lineWidth: max(0.5, s * 0.02))

            // Crisp defining rim so the gem never washes out against light/translucent backgrounds.
            ctx.stroke(outline(s), with: .color(Self.shade(28, 86, 158).opacity(0.55)), lineWidth: max(0.6, s * 0.025))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
