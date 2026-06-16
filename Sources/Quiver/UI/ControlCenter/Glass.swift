import SwiftUI

/// Control-Center glass, drawn with SwiftUI materials (Liquid Glass on macOS 26, `.regularMaterial`
/// below). Renders reliably inside the floating panel; falls back to a solid fill when Reduce
/// Transparency is on.
private struct GlassBackdrop<S: Shape>: View {
    var shape: S
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            shape.fill(Color(nsColor: .controlBackgroundColor))
        } else if #available(macOS 26.0, *) {
            shape.fill(.clear).glassEffect(.regular, in: shape)
        } else {
            shape.fill(.regularMaterial)
        }
    }
}

extension View {
    /// A rounded-rect glass tile (Wi-Fi / Focus / sliders / large controls), with a subtle glass rim.
    func ccGlassRect(_ cornerRadius: CGFloat = 26) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return background(GlassBackdrop(shape: shape))
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5))
    }

    /// A circular / capsule glass control (1×1 toggles, the floating chrome capsules).
    func ccGlassCapsule() -> some View {
        background(GlassBackdrop(shape: Capsule()))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5))
    }
}
