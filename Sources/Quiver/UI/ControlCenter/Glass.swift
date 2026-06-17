import SwiftUI
import AppKit

/// Control-Center glass. macOS 26's `NSGlassEffectView` is the *real* Liquid Glass material — it
/// "pulls pixels from the desktop and windows behind it" (so it frosts the wallpaper like Control
/// Center, independent of light/dark mode) AND renders the specular/lensing highlights that a plain
/// `NSVisualEffectView` or SwiftUI `glassEffect` can't. Used natively (not as a SwiftUI `glassEffect`,
/// which the hosting layer prevents from sampling the desktop). Corners come from its own
/// `cornerRadius`. Falls back to behind-window `NSVisualEffectView` (rounded via `maskImage`) on macOS
/// < 26, and a solid fill under Reduce Transparency.
/// An `NSGlassEffectView` configured with the *exact* material macOS Control Center uses. Two things make
/// it match CC instead of looking like a generic frosted panel:
///
///  1. **`_variant = 8` ("controlCenter")** — `NSGlassEffectView`'s public `.regular`/`.clear` styles are
///     only approximations (`.regular` reads too milky, `.clear` too bare/edgeless — verified by
///     back-to-back captures over the same wallpaper). Variant 8 is the literal Control Center recipe:
///     translucent body, a defined specular rim, and wallpaper sampling. It's private SPI (`set_variant:`),
///     guarded by `responds(to:)` so a future rename silently degrades to plain `.clear` — still valid glass.
///  2. **Never "subdued."** The system flattens the glass to a milky frost whenever its window isn't key —
///     and the hub is a nonactivating panel that is *never* key, so it would frost permanently. Overriding
///     the private `_subduedState` getter to always report `0` keeps the live, lensed CC render at all times.
///
/// OK to use private SPI here: Quiver is ad-hoc-signed (not App Store) and already links private frameworks
/// (SkyLight, via `MenuBarReveal`). Both hooks fail safe.
@available(macOS 26.0, *)
private final class CCGlassView: NSGlassEffectView {
    @objc(_subduedState) func subduedStateGetterOverride() -> Int { 0 }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyControlCenterMaterial()
    }

    func applyControlCenterMaterial() {
        style = .clear
        let sel = NSSelectorFromString("set_variant:")
        guard responds(to: sel) else { return }
        let imp = method(for: sel)
        unsafeBitCast(imp, to: (@convention(c) (NSObject, Selector, Int) -> Void).self)(self, sel, 8)
    }
}

/// `effectIsInteractive` drives the live specular "lensing" as content moves under the glass — the exact
/// effect Control Center shows. It isn't declared on `NSGlassEffectView` in current SDKs, so set it via the
/// runtime (guarded by `responds(to:)`) rather than a compile-time symbol: that keeps the build working on
/// SDKs that lack it and silently enables it on OSes/SDKs that have it.
@available(macOS 26.0, *)
private func setEffectInteractive(_ view: NSGlassEffectView) {
    let sel = NSSelectorFromString("setEffectIsInteractive:")
    guard view.responds(to: sel) else { return }
    view.setValue(true, forKey: "effectIsInteractive")
}

@available(macOS 26.0, *)
private struct LiquidGlass: NSViewRepresentable {
    var cornerRadius: CGFloat
    var tint: NSColor?

    func makeNSView(context: Context) -> NSGlassEffectView {
        let view = CCGlassView()
        view.cornerRadius = cornerRadius
        view.tintColor = tint
        view.applyControlCenterMaterial()
        setEffectInteractive(view)
        return view
    }

    func updateNSView(_ view: NSGlassEffectView, context: Context) {
        view.cornerRadius = cornerRadius
        view.tintColor = tint
        (view as? CCGlassView)?.applyControlCenterMaterial()
        setEffectInteractive(view)
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
            // The real system Control Center glass material (private variant 8) — no fill/rim approximations.
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
