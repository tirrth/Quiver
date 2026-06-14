import AppKit

/// A translucent, click-through overlay that previews where a dragged window will snap. It's a
/// borderless non-activating panel so it never steals the drag or the user's focus.
@MainActor
final class SnapPreviewWindow {
    private let panel: NSPanel
    private let box: NSView

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        box = NSView()
        box.wantsLayer = true
        if let layer = box.layer {
            layer.cornerRadius = 10
            layer.cornerCurve = .continuous
            layer.borderWidth = 2.5
            layer.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.22).cgColor
            layer.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.9).cgColor
        }
        panel.contentView = box
    }

    /// Show (or move) the preview to `frame` (AppKit, bottom-left coordinates), fading in the first time.
    func show(frame: CGRect) {
        // Re-read the accent colour each time in case the system tint changed.
        box.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.22).cgColor
        box.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.9).cgColor
        if panel.isVisible {
            panel.setFrame(frame, display: true, animate: true)
        } else {
            panel.setFrame(frame, display: false)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                panel.animator().alphaValue = 1
            }
        }
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
    }
}
