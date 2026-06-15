import AppKit
import SwiftUI

/// A borderless, menu-like panel that hosts SwiftUI content just below a menu-bar icon. Unlike an
/// NSPopover it has no arrow, and — being a real window — any SwiftUI control works inside it
/// (pickers, text fields, lists). It dismisses on a click outside, on Escape, or when shown again.
@MainActor
final class AnchoredPanel {
    private var panel: KeyablePanel?
    private var clickMonitor: Any?
    private var escMonitor: Any?

    /// Called whenever the panel closes (e.g. to clear the menu-bar icon highlight).
    var onClose: (() -> Void)?

    var isShown: Bool { panel?.isVisible ?? false }

    func show<Content: View>(_ content: Content, below anchor: CGRect) {
        close()
        let host = NSHostingController(rootView:
            content
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1))
        )
        host.view.layoutSubtreeIfNeeded()
        let size = host.view.fittingSize

        let p = KeyablePanel(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .popUpMenu
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        p.isReleasedWhenClosed = false
        p.contentViewController = host

        // Position just below the icon, centred and clamped to the screen. Set the full frame (with
        // the size) explicitly — assigning a contentViewController otherwise collapses it to 0×0.
        let screen = NSScreen.screens.first { NSMouseInRect(NSPoint(x: anchor.midX, y: anchor.midY), $0.frame, false) } ?? NSScreen.main
        var x = anchor.midX - size.width / 2
        if let vf = screen?.visibleFrame {
            x = min(max(x, vf.minX + 8), vf.maxX - size.width - 8)
        }
        let originY = anchor.minY - 4 - size.height   // hang the panel below the icon
        p.setFrame(NSRect(x: x, y: originY, width: size.width, height: size.height), display: true)
        p.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        panel = p
        installMonitors()
    }

    func close() {
        removeMonitors()
        panel?.orderOut(nil)
        panel = nil
        onClose?()
    }

    private func installMonitors() {
        // A click anywhere outside the panel dismisses it. Global monitors don't fire for our own
        // clicks, so interacting with the controls keeps it open.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.close()
        }
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.close(); return nil }   // Esc
            return event
        }
    }

    private func removeMonitors() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        if let escMonitor { NSEvent.removeMonitor(escMonitor) }
        clickMonitor = nil
        escMonitor = nil
    }
}

/// A borderless panel that can still become key, so the SwiftUI controls inside accept input.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
