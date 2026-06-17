import AppKit
import SwiftUI

/// The Control-Center-style floating hub: a borderless glass panel anchored under the menu-bar icon,
/// like macOS Control Center. Dismisses on click-outside or Escape, and re-lays out (keeping its top
/// edge fixed, growing downward) when its SwiftUI content changes height (Edit mode, resize, add/remove).
@MainActor
final class HubPanel {
    private var panel: NSPanel?
    private weak var anchorButton: NSStatusBarButton?
    private var host: NSHostingController<AnyView>?
    private let backdrop = HubBackdrop()   // the CC-style background blur behind the panel
    private var clickMonitor: Any?
    private var escMonitor: Any?
    private var activationObserver: NSObjectProtocol?
    private var anchorTopCenter: CGPoint = .zero   // fixed top-center so the panel grows downward
    private var anchorScreen: NSScreen?            // the screen the gem lives on (never re-guessed)

    /// Called when the panel closes (to drop the icon highlight).
    var onClose: (() -> Void)?

    var isShown: Bool { panel?.isVisible ?? false }

    func toggle(_ content: AnyView, below button: NSStatusBarButton?) {
        if isShown { close() } else { show(content, below: button) }
    }

    func show(_ content: AnyView, below button: NSStatusBarButton?) {
        close(notify: false)
        anchorButton = button
        button?.highlight(true)

        let host = NSHostingController(rootView: content)
        host.view.layoutSubtreeIfNeeded()
        let size = host.view.fittingSize

        // Borderless, nonactivating glass panel. It becomes key so SwiftUI controls receive clicks, but
        // never becomes a main app window; when another app activates, we close it immediately so the
        // glass never lingers in an inactive/frosted recipe.
        let panel = ControlCenterPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.becomesKeyOnlyIfNeeded = true
        // Set `isFloatingPanel` BEFORE `level` — it resets the level to `.floating`, so setting the level
        // afterward keeps the panel at `.popUpMenu` (above the menu bar / other floating windows).
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        // `.moveToActiveSpace` brings the panel onto the space the user is currently looking at — including
        // a full-screen app's space (with `.fullScreenAuxiliary`). The old `.canJoinAllSpaces` stranded it
        // on the desktop space, so over a full-screen app the panel "disappeared". (The two space flags are
        // mutually exclusive; this matches Ice's IceBar config.)
        panel.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle, .moveToActiveSpace]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.contentViewController = host

        self.host = host
        self.panel = panel

        if let (anchor, screen) = topCenterAnchor(for: button) {
            anchorTopCenter = anchor
            anchorScreen = screen
        } else {
            // Status item not positioned yet (fresh launch): provisionally center at the top of the screen
            // *under the cursor* (where the click happened) — NOT NSScreen.main, which may be a different
            // display than the one holding the gem. Then retry once the item settles to land under the icon.
            let screen = screenWithMouse() ?? NSScreen.main
            let vf = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            anchorScreen = screen
            anchorTopCenter = CGPoint(x: vf.midX, y: screen?.frame.maxY ?? vf.maxY)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self, let button = self.anchorButton,
                      let (anchor, screen) = self.topCenterAnchor(for: button) else { return }
                self.anchorTopCenter = anchor
                self.anchorScreen = screen
                self.relayout()
            }
        }
        positionPanel(size: size)
        // Keep the system menu bar revealed for the panel's lifetime — including over a full-screen app,
        // where it auto-hides (a floating panel can't hold it via menu tracking). SkyLight SPI; restored on
        // close. The panel is key for controls, but nonactivating and closed on app activation changes.
        MenuBarReveal.reveal()
        // The CC-style background blur sits one window below the hub; order the hub directly above it.
        if let screen = anchorScreen { backdrop.show(on: screen, hubFrame: panel.frame) }
        panel.makeKeyAndOrderFront(nil)
        if let backdropNumber = backdrop.windowNumber { panel.order(.above, relativeTo: backdropNumber) }
        installMonitors()
    }

    /// Re-measure and resize, keeping the top-right corner fixed (grow downward like Control Center).
    func relayout() {
        guard let panel, let host else { return }
        host.view.layoutSubtreeIfNeeded()
        positionPanel(size: host.view.fittingSize)
        if let screen = anchorScreen { backdrop.update(on: screen, hubFrame: panel.frame) }
    }

    func close() {
        close(notify: true)
    }

    private func close(notify: Bool) {
        removeMonitors()
        panel?.orderOut(nil)
        backdrop.hide()
        panel = nil
        host = nil
        MenuBarReveal.restore()   // put the user's menu-bar auto-hide setting back
        if notify { onClose?() }
    }

    // MARK: Geometry

    /// The on-screen top-center point just below the gem, plus the screen it lives on. Returns nil while
    /// the status item isn't yet positioned (its frame isn't flush to a menu bar), so the caller retries.
    private func topCenterAnchor(for button: NSStatusBarButton?) -> (point: CGPoint, screen: NSScreen)? {
        guard let button, let window = button.window else { return nil }
        let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
        // The screen must come from the *button's own window*, not a geometric search or NSScreen.main —
        // that's what handles multi-display + notched layouts correctly (mirrors Ice / Apple DTS guidance).
        guard let screen = window.screen ?? NSScreen.screens.first(where: { $0.frame.intersects(frame) }) else {
            return nil
        }
        // The button is in the menu bar iff its vertical center sits above the screen's *visible* area
        // (`visibleFrame` excludes the menu bar). This is geometry-derived, so it's correct on the taller
        // macOS 26/27 bar and on notched displays — unlike the old "within 4pt of the very top" test, which
        // failed on Tahoe (the status item is inset ~5.5pt from the top) and made the panel always fall back.
        guard frame.midY >= screen.visibleFrame.maxY else { return nil }
        let topY = min(frame.minY, screen.visibleFrame.maxY) - 6   // just below the bar / icon, CC-like gap
        return (CGPoint(x: frame.midX, y: topY), screen)   // just below the icon, horizontally centered
    }

    /// The screen currently under the mouse (where the menu-bar click happened), for the launch-race fallback.
    private func screenWithMouse() -> NSScreen? {
        let loc = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(loc, $0.frame, false) }
    }

    private func positionPanel(size: NSSize) {
        guard let panel else { return }
        // Use the screen resolved when we took the anchor — never re-derive via NSScreen.main, which is the
        // bug that pushed the panel onto the wrong display.
        let screen = anchorScreen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        // Center the panel under the menu-bar icon; the content is centered within the panel (the
        // transparent shadow padding is symmetric), so the icon sits over the middle of the grid.
        var x = anchorTopCenter.x - size.width / 2
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        // Keep the whole panel on-screen vertically too — a safety net so a stale/off-screen anchor can
        // never push it off the bottom (the pre-fix bug).
        var y = anchorTopCenter.y - size.height   // top edge fixed → grows downward
        y = min(max(y, visible.minY + 8), visible.maxY - size.height)
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }

    // MARK: Dismissal

    private func installMonitors() {
        // A global monitor sees mouse-downs the system posts to *other* apps. Because our panel is
        // nonactivating (Quiver never becomes the active app), clicks ON the panel are ALSO reported here —
        // so closing unconditionally would dismiss the panel on its own controls (and made it "disappear"
        // the moment it opened over another app). Only close when the click is genuinely OUTSIDE the panel.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, let panel = self.panel else { return }
            if !panel.frame.contains(NSEvent.mouseLocation) { self.close() }
        }
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.close(); return nil }   // Esc
            return event
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if app?.bundleIdentifier != Bundle.main.bundleIdentifier {
                Task { @MainActor in self?.close() }
            }
        }
    }

    private func removeMonitors() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        if let escMonitor { NSEvent.removeMonitor(escMonitor) }
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        clickMonitor = nil
        escMonitor = nil
        activationObserver = nil
    }
}

/// A borderless Control-Center panel that can receive control clicks without turning into a main app
/// window. The hub closes on app activation changes, so it does not remain visible as inactive glass.
final class ControlCenterPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
