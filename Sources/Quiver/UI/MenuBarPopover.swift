import AppKit
import SwiftUI

/// A borderless panel that can become key without activating the app (so Escape/keyboard work in a
/// menu-bar popover without stealing the user's app focus).
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Quiver's menu-bar popover, implemented the way native menu-bar apps do it (no NSPopover arrow):
/// a borderless panel anchored under the status item, that highlights the icon while open and
/// dismisses on any outside click, Escape, a Space/Mission-Control change, or a second click of the
/// icon. All dismissal hooks are torn down on close.
@MainActor
final class MenuBarPopover {
    private let panel: KeyablePanel
    private let hostingController: NSHostingController<AnyView>
    private weak var button: NSStatusBarButton?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var keyMonitor: Any?
    private var spaceObserver: NSObjectProtocol?
    private var activateObserver: NSObjectProtocol?

    private(set) var isShown = false

    init(content: AnyView) {
        hostingController = NSHostingController(rootView: content)
        panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 420),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu                 // above floating windows + visible over fullscreen
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentViewController = hostingController
    }

    func toggle(relativeTo button: NSStatusBarButton) {
        isShown ? close() : show(relativeTo: button)
    }

    func show(relativeTo button: NSStatusBarButton) {
        guard !isShown, let buttonWindow = button.window else { return }
        self.button = button

        // Size to the SwiftUI content.
        hostingController.view.layoutSubtreeIfNeeded()
        let size = hostingController.view.fittingSize

        // Anchor centered under the icon, clamped onto the icon's screen.
        let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let gap: CGFloat = 6
        var x = buttonRect.midX - size.width / 2
        x = max(visible.minX + 8, min(x, visible.maxX - size.width - 8))
        let y = buttonRect.minY - size.height - gap
        let target = NSRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height)

        // Drop-in animation.
        panel.setFrame(target.offsetBy(dx: 0, dy: 8), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.13
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 1
        }

        button.highlight(true)
        isShown = true
        installMonitors()
    }

    func close() {
        guard isShown else { return }
        isShown = false
        removeMonitors()
        button?.highlight(false)
        let win = panel
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.09
            win.animator().alphaValue = 0
        }, completionHandler: {
            win.orderOut(nil)
            win.alphaValue = 1
        })
    }

    // MARK: Dismissal hooks

    private func installMonitors() {
        // Clicks in other apps / the desktop.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.close()
        }
        // Clicks within our own app (e.g. the main window) outside the panel — but not on the status
        // icon, whose own action toggles the popover (so we don't double-handle / reopen).
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            if event.window == self.panel { return event }
            if self.isOnStatusButton(event) { return event }
            self.close()
            return event
        }
        // Escape.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 { self?.close(); return nil }
            return event
        }
        // Switching Space / opening Mission Control.
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
        // Switching to another app (e.g. cmd-tab, which a mouse monitor wouldn't catch). Ignore our
        // own activation (opening a Quiver window from the popover).
        activateObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if app?.bundleIdentifier == Bundle.main.bundleIdentifier { return }
            Task { @MainActor in self?.close() }
        }
    }

    private func removeMonitors() {
        for monitor in [globalMonitor, localMonitor, keyMonitor].compactMap({ $0 }) {
            NSEvent.removeMonitor(monitor)
        }
        globalMonitor = nil
        localMonitor = nil
        keyMonitor = nil
        if let spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)
        }
        if let activateObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activateObserver)
        }
        spaceObserver = nil
        activateObserver = nil
    }

    private func isOnStatusButton(_ event: NSEvent) -> Bool {
        guard let button, let buttonWindow = button.window else { return false }
        if event.window == buttonWindow { return true }
        let rect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        return NSMouseInRect(NSEvent.mouseLocation, rect, false)
    }
}
