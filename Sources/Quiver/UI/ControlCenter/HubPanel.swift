import AppKit
import SwiftUI

/// The Control-Center-style floating hub: a borderless glass panel anchored under the menu-bar icon,
/// like macOS Control Center. Dismisses on click-outside or Escape, and re-lays out (keeping its top
/// edge fixed, growing downward) when its SwiftUI content changes height (Edit mode, resize, add/remove).
@MainActor
final class HubPanel {
    private var panel: KeyablePanel?
    private weak var anchorButton: NSStatusBarButton?
    private var host: NSHostingController<AnyView>?
    private var clickMonitor: Any?
    private var escMonitor: Any?
    private var anchorTopCenter: CGPoint = .zero   // fixed top-center so the panel grows downward

    /// Called when the panel closes (to drop the icon highlight).
    var onClose: (() -> Void)?

    var isShown: Bool { panel?.isVisible ?? false }

    func toggle(_ content: AnyView, below button: NSStatusBarButton?) {
        if isShown { close() } else { show(content, below: button) }
    }

    func show(_ content: AnyView, below button: NSStatusBarButton?) {
        close()
        anchorButton = button

        let host = NSHostingController(rootView: content)
        host.view.layoutSubtreeIfNeeded()
        let size = host.view.fittingSize

        let panel = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        // Quiver is an LSUIElement (agent) app with no menu bar of its own. If this panel ever became
        // the key window while the app is in `.accessory` mode, macOS would make our agent app the
        // menu-bar owner and — finding no menu bar — hide the whole system bar. So the panel must show
        // without becoming key or activating the app: a nonactivating panel that only takes key focus
        // if a control truly needs it (we have none), ordered front without activation. Controls still
        // receive clicks (nonactivating panels deliver mouse events without stealing focus).
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.contentViewController = host

        self.host = host
        self.panel = panel

        anchorTopCenter = topCenterAnchor(for: button) ?? CGPoint(x: 0, y: 0)
        positionPanel(size: size)
        // Tell the system a menu bar item is "tracking" so the menu bar stays revealed while we're open
        // on top of a full-screen app (where it would otherwise auto-hide). This is the technique system
        // items / Control Center rely on; it lets our floating panel keep the bar pinned without being an
        // actual NSMenu. Just a distributed-notification name — no private frameworks, degrades safely.
        Self.postMenuTracking(begin: true)
        panel.orderFrontRegardless()
        installMonitors()
    }

    /// Posting `begin…` keeps the menu bar revealed over a full-screen app while the panel is open;
    /// `end…` reverses it. (HIToolbox distributed notifications, the same ones real menu tracking posts.)
    private static func postMenuTracking(begin: Bool) {
        let name = begin ? "com.apple.HIToolbox.beginMenuTrackingNotification"
                         : "com.apple.HIToolbox.endMenuTrackingNotification"
        DistributedNotificationCenter.default().post(name: Notification.Name(name), object: nil)
    }

    /// Re-measure and resize, keeping the top-right corner fixed (grow downward like Control Center).
    func relayout() {
        guard let panel, let host else { return }
        host.view.layoutSubtreeIfNeeded()
        positionPanel(size: host.view.fittingSize)
        _ = panel
    }

    func close() {
        let wasShown = panel != nil
        removeMonitors()
        panel?.orderOut(nil)
        panel = nil
        host = nil
        if wasShown { Self.postMenuTracking(begin: false) }   // release the menu-bar pin
        onClose?()
    }

    // MARK: Geometry

    private func topCenterAnchor(for button: NSStatusBarButton?) -> CGPoint? {
        guard let button, let window = button.window else { return nil }
        let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
        return CGPoint(x: frame.midX, y: frame.minY - 6)   // just below the icon, horizontally centered
    }

    private func positionPanel(size: NSSize) {
        guard let panel else { return }
        let screen = NSScreen.screens.first { NSPointInRect(NSPoint(x: anchorTopCenter.x, y: anchorTopCenter.y), $0.frame) } ?? NSScreen.main
        // Center the panel under the menu-bar icon; the content is centered within the panel (the
        // transparent shadow padding is symmetric), so the icon sits over the middle of the grid.
        var x = anchorTopCenter.x - size.width / 2
        if let visible = screen?.visibleFrame {
            x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        }
        let y = anchorTopCenter.y - size.height   // top edge fixed → grows downward
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }

    // MARK: Dismissal

    private func installMonitors() {
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
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
