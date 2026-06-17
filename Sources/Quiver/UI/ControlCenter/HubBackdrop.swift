import AppKit
import QuartzCore
import CoreImage

/// The Control-Center "background blur": when the hub opens, the desktop *and other app windows* behind it
/// blur — strongest around the panel, feathering to fully sharp toward the screen edges (a soft halo), with
/// the menu bar left untouched. It is a separate, transparent, mouse-ignoring panel sitting one step **below**
/// the hub and **above** every other window, so it never interferes with the hub's clicks or dismissal.
///
/// Why a separate window: a behind-window blur only blurs what is rendered *behind its window*. The hub
/// itself must stay crisp on top, so the blur lives in its own window underneath. The blur is a **pure,
/// tint-free Gaussian** (private `CABackdropLayer`, the primitive the system uses) — not the milky tint an
/// `NSVisualEffectView` material adds — feathered with a rounded-rect mask that traces the hub's outline (so
/// the halo is the panel's shape, with breathing room, fading out), matching real Control Center's backdrop.
@MainActor
final class HubBackdrop {
    // MARK: Tuning (safe to tweak)
    /// Gaussian blur radius (points) of the backdrop content. Light, like a gentle frost.
    private static let blurRadius: CGFloat = 3
    /// Subtle dark dim laid over the blur (0 = none), feathered with the same halo so it fades out at the
    /// edges — the slight darkening real Control Center adds for separation. Keep it gentle ("not blackish").
    private static let dimOpacity: CGFloat = 0.1
    /// Spacing the *full-strength* blur extends beyond the hub's outline before it begins to fade — the gap
    /// that lets the halo trace the panel shape with a little breathing room.
    private static let featherInset: CGFloat = 18
    /// The distance over which the blur fades from full strength to fully clear (the soft halo edge).
    private static let featherWidth: CGFloat = 70
    /// Corner radius of the rounded-rect halo (so it matches the hub's outline rather than being a circle).
    private static let cornerRadius: CGFloat = 20
    private static let fadeIn: TimeInterval = 0.22
    private static let fadeOut: TimeInterval = 0.16

    private var window: NSPanel?
    private var view: FeatheredBackdropView?

    /// Show the blur on `screen`, feathered around `hubFrame` (in screen coordinates).
    func show(on screen: NSScreen, hubFrame: NSRect) {
        // Reduce Transparency: macOS users who opt out of vibrancy shouldn't get a screen-wide blur. Skip it
        // entirely (no backdrop window) — the hub itself already falls back to a solid fill in this mode.
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency else { return }
        let firstShow = (window == nil)
        present(on: screen, hubFrame: hubFrame)
        guard let win = window else { return }
        if firstShow {
            win.alphaValue = 0
            win.orderFront(nil)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = Self.fadeIn
                win.animator().alphaValue = 1
            }
        } else {
            win.orderFront(nil)
        }
    }

    /// Re-target/re-feather after the hub moves/resizes (Edit mode, add/remove, the launch-race reposition
    /// — which can even land on a different display, so this re-frames the window to the current screen too).
    func update(on screen: NSScreen, hubFrame: NSRect) {
        guard window != nil else { return }
        present(on: screen, hubFrame: hubFrame)
    }

    /// Build/re-frame the backdrop window to cover `screen` and feather the blur around `hubFrame`.
    private func present(on screen: NSScreen, hubFrame: NSRect) {
        // Cover the usable area (below the menu bar) so the menu bar itself is never blurred — like CC.
        let frame = screen.visibleFrame
        let win = window ?? makeWindow(frame: frame)
        win.setFrame(frame, display: false)

        let v = view ?? FeatheredBackdropView(frame: NSRect(origin: .zero, size: frame.size),
                                              blurRadius: Self.blurRadius, dimOpacity: Self.dimOpacity)
        v.frame = NSRect(origin: .zero, size: frame.size)
        win.contentView = v
        v.feather(hubFrameInScreen: hubFrame, windowOrigin: frame.origin,
                  spacing: Self.featherInset, fade: Self.featherWidth, corner: Self.cornerRadius)

        window = win
        view = v
    }

    func hide() {
        guard let win = window else { return }
        window = nil
        view = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = Self.fadeOut
            win.animator().alphaValue = 0
        }, completionHandler: {
            win.orderOut(nil)
        })
    }

    /// The window number, so the hub can guarantee it orders itself directly above the backdrop.
    var windowNumber: Int? { window?.windowNumber }

    private func makeWindow(frame: NSRect) -> NSPanel {
        let win = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                          backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = false
        // Purely decorative: clicks pass straight through to whatever is behind, so the hub's existing
        // click-outside / app-activation dismissal keeps working without any changes.
        win.ignoresMouseEvents = true
        // Same level band as the hub (above the menu bar's window band), but the hub is ordered above it.
        win.isFloatingPanel = true
        win.level = .popUpMenu
        // Match the hub panel's proven space config so the blur follows it onto the active (incl. full-screen)
        // space. `.canJoinAllSpaces`/`.stationary` are deliberately avoided (they stranded the hub off-space).
        win.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle, .moveToActiveSpace]
        win.isReleasedWhenClosed = false
        win.hidesOnDeactivate = false
        return win
    }
}

/// A pure, tint-free behind-window blur clipped to a soft **rounded-rect halo that traces the hub's outline**
/// (not a circle). Primary path is a private `CABackdropLayer` (samples the window-server content behind the
/// window and applies a Gaussian with no color overlay) masked by a feathered rounded-rect alpha image. If
/// the private class is ever unavailable it falls back to a masked `NSVisualEffectView` (works everywhere,
/// but adds the material's tint).
final class FeatheredBackdropView: NSView {
    private var backdropLayer: CALayer?            // CABackdropLayer (pure blur), when available
    private var visualEffect: NSVisualEffectView?  // fallback (tinted)
    private let maskLayer = CALayer()              // contents = feathered rounded-rect alpha image (blur)
    private let dimLayer = CALayer()               // subtle dark wash on top of the blur
    private let dimMaskLayer = CALayer()           // same feather image as maskLayer (dim feathers identically)
    private static let ciContext = CIContext()

    init(frame: NSRect, blurRadius: CGFloat, dimOpacity: CGFloat) {
        super.init(frame: frame)
        wantsLayer = true
        layerUsesCoreImageFilters = false

        maskLayer.frame = bounds
        maskLayer.contentsGravity = .resize

        if let backdrop = Self.makeBackdropLayer(radius: blurRadius) {
            backdrop.frame = bounds
            backdrop.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            backdrop.mask = maskLayer
            layer?.addSublayer(backdrop)
            backdropLayer = backdrop
        } else {
            let effect = NSVisualEffectView(frame: bounds)
            effect.autoresizingMask = [.width, .height]
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.material = .fullScreenUI
            addSubview(effect)
            visualEffect = effect
        }

        // The CC-style dim: a flat dark layer on top of the blur, clipped by an identical feather mask so it
        // darkens the same halo and fades out with it (a separate mask layer — a CALayer mask can back only
        // one layer). Skipped entirely at 0.
        if dimOpacity > 0 {
            dimMaskLayer.frame = bounds
            dimMaskLayer.contentsGravity = .resize
            dimLayer.frame = bounds
            dimLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            dimLayer.backgroundColor = NSColor.black.withAlphaComponent(dimOpacity).cgColor
            dimLayer.mask = dimMaskLayer
            layer?.addSublayer(dimLayer)   // added after the blur → sits on top of it
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Rebuild the feather: a rounded rect tracing the hub (expanded by `spacing`), then its edges blurred so
    /// it fades to clear over `fade`. The result is a soft halo the *shape of the hub*, not a circle.
    func feather(hubFrameInScreen: NSRect, windowOrigin: CGPoint, spacing: CGFloat, fade: CGFloat, corner: CGFloat) {
        let b = bounds
        guard b.width > 1, b.height > 1 else { return }
        // Hub rect in the mask image's top-down coordinates (CALayer `contents` / NSImage both read top-down).
        let hubRect = CGRect(x: hubFrameInScreen.minX - windowOrigin.x,
                             y: b.height - (hubFrameInScreen.minY - windowOrigin.y) - hubFrameInScreen.height,
                             width: hubFrameInScreen.width, height: hubFrameInScreen.height)
        let image = Self.featherMaskImage(viewSize: b.size, hubRect: hubRect,
                                          spacing: spacing, fade: fade, corner: corner)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        maskLayer.frame = b
        maskLayer.contents = image
        dimMaskLayer.frame = b
        dimMaskLayer.contents = image
        visualEffect?.maskImage = image.map { NSImage(cgImage: $0, size: b.size) }
        CATransaction.commit()
    }

    // MARK: Private blur engine (SPI, fails safe to NSVisualEffectView)

    private static func makeBackdropLayer(radius: CGFloat) -> CALayer? {
        guard let backdropClass = NSClassFromString("CABackdropLayer") as? CALayer.Type else { return nil }
        let backdrop = backdropClass.init()
        // Capture the window-server content behind the window (other apps + desktop), not just in-window.
        // Guard the private setter with `responds(to:)`: KVC would *crash* on a renamed key, so if it's gone
        // we bail and let the caller use the functional (if tinted) NSVisualEffectView fallback instead.
        guard backdrop.responds(to: NSSelectorFromString("setWindowServerAware:")),
              let blur = gaussianFilter(radius: radius) else { return nil }   // else: NSVisualEffectView fallback
        backdrop.setValue(true, forKey: "windowServerAware")
        backdrop.filters = [blur]
        return backdrop
    }

    private static func gaussianFilter(radius: CGFloat) -> NSObject? {
        guard let filterClass = NSClassFromString("CAFilter") as AnyObject as? NSObjectProtocol else { return nil }
        let sel = NSSelectorFromString("filterWithName:")
        guard filterClass.responds(to: sel),
              let filter = filterClass.perform(sel, with: "gaussianBlur")?.takeUnretainedValue() as? NSObject
        else { return nil }
        filter.setValue(radius, forKey: "inputRadius")
        filter.setValue(true, forKey: "inputNormalizeEdges")
        return filter
    }

    /// A feathered rounded-rect alpha mask the *shape of the hub*: fill a rounded rect (the hub expanded by
    /// `spacing`, plus the blur's own spread so the plateau still covers it), then Gaussian-blur it so its
    /// edges fade to clear over ~`fade`. Drawn top-down (row 0 = top) so it reads correctly both as a CALayer
    /// `contents` mask and as an `NSImage` `maskImage`. Rendered at point resolution — plenty for a soft mask.
    private static func featherMaskImage(viewSize: CGSize, hubRect: CGRect,
                                         spacing: CGFloat, fade: CGFloat, corner: CGFloat) -> CGImage? {
        let sigma = max(1, fade / 3)            // a Gaussian fades over ~3σ
        let expand = spacing + sigma            // over-expand so the blur eats back to (hub + spacing)
        let rect = hubRect.insetBy(dx: -expand, dy: -expand)
        let radius = min(corner + expand, min(rect.width, rect.height) / 2)

        let w = max(1, Int(viewSize.width)), h = max(1, Int(viewSize.height))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // Flip to top-down points so the drawn shape lands where CA/NSImage will read it.
        ctx.translateBy(x: 0, y: viewSize.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.fillPath()
        guard let filled = ctx.makeImage() else { return nil }

        let input = CIImage(cgImage: filled)
        guard let blur = CIFilter(name: "CIGaussianBlur") else { return filled }
        blur.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)   // clamp so edges don't darken
        blur.setValue(sigma, forKey: kCIInputRadiusKey)
        guard let output = blur.outputImage,
              let result = ciContext.createCGImage(output, from: input.extent) else { return filled }
        return result
    }
}
