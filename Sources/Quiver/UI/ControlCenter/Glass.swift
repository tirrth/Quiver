import SwiftUI
import AppKit

/// Control-Center glass. macOS 26's `NSGlassEffectView` is the *real* Liquid Glass material — it
/// "pulls pixels from the desktop and windows behind it" (so it frosts the wallpaper like Control
/// Center, independent of light/dark mode) AND renders the specular/lensing highlights that a plain
/// `NSVisualEffectView` or SwiftUI `glassEffect` can't. Used natively (not as a SwiftUI `glassEffect`,
/// which the hosting layer prevents from sampling the desktop). Corners come from its own
/// `cornerRadius`. Falls back to behind-window `NSVisualEffectView` (rounded via `maskImage`) on macOS
/// < 26, and a solid fill under Reduce Transparency.
@available(macOS 26.0, *)
private struct LiquidGlass: NSViewRepresentable {
    var cornerRadius: CGFloat
    var tint: NSColor?

    func makeNSView(context: Context) -> NSGlassEffectView {
        let view = NSGlassEffectView()
        view.cornerRadius = cornerRadius
        view.tintColor = tint
        view.style = .clear   // more translucent (shows the wallpaper through), like Control Center
        return view
    }

    func updateNSView(_ view: NSGlassEffectView, context: Context) {
        view.cornerRadius = cornerRadius
        view.tintColor = tint
        view.style = .clear
    }
}

/// Pre-macOS-26 fallback: behind-window vibrancy frosting the wallpaper. CRITICAL: round with
/// `maskImage`, NOT `layer.cornerRadius`/`masksToBounds`, which disables the blur (renders transparent).
private struct WallpaperGlass: NSViewRepresentable {
    var cornerRadius: CGFloat
    var material: NSVisualEffectView.Material = .menu

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = material
        view.state = .active
        view.appearance = NSAppearance(named: .aqua)   // light frost, like Control Center
        view.maskImage = Self.roundedMask(cornerRadius)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.maskImage = Self.roundedMask(cornerRadius)
    }

    private static func roundedMask(_ r: CGFloat) -> NSImage {
        let edge = max(1, 2 * r) + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: r, left: r, bottom: r, right: r)
        image.resizingMode = .stretch
        return image
    }
}

/// The frosted backdrop: real Liquid Glass on macOS 26, behind-window vibrancy below, solid when
/// Reduce Transparency is on.
private struct GlassBackdrop: View {
    var cornerRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        } else if #available(macOS 26.0, *) {
            LiquidGlass(cornerRadius: cornerRadius)
        } else {
            WallpaperGlass(cornerRadius: cornerRadius)
        }
    }
}

extension View {
    /// A rounded-rect glass tile (wide / large tiles, the floating chrome).
    func ccGlassRect(_ cornerRadius: CGFloat = 26) -> some View {
        background(GlassBackdrop(cornerRadius: cornerRadius))
    }

    /// A circular / capsule glass control (1×1 tiles, header/footer chrome). The radius is read from the
    /// host's size so it rounds to a true capsule/circle.
    func ccGlassCapsule() -> some View {
        background(
            GeometryReader { geo in
                GlassBackdrop(cornerRadius: min(geo.size.width, geo.size.height) / 2)
            }
        )
    }
}
