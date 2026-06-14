import AppKit
import SwiftUI

/// Borderless panel that can become key (so its controls behave like a normal window and Escape works).
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Quiver's menu-bar popover — a borderless panel (no NSPopover arrow) anchored under the status item.
/// It activates and becomes key on open so every control works on the first click, highlights the
/// icon, and dismisses the moment it loses key focus (click anywhere else, switch apps, Escape, or a
/// second click of the icon). Simple and reliable — no manual event-monitor juggling.
@MainActor
final class MenuBarPopover: NSObject, NSWindowDelegate {
    private let panel: KeyablePanel
    private let hostingController: NSHostingController<AnyView>
    private weak var button: NSStatusBarButton?

    private var escMonitor: Any?
    private var spaceObserver: NSObjectProtocol?
    /// Guards against the icon click that closed the popover immediately reopening it.
    private var ignoreOpenUntil = Date.distantPast

    private(set) var isShown = false

    init(content: AnyView) {
        hostingController = NSHostingController(rootView: content)
        panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 420),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.delegate = self
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentViewController = hostingController
    }

    func toggle(relativeTo button: NSStatusBarButton) {
        if isShown {
            close()
        } else if Date() >= ignoreOpenUntil {
            show(relativeTo: button)
        }
    }

    func show(relativeTo button: NSStatusBarButton) {
        guard !isShown, let buttonWindow = button.window else { return }
        self.button = button

        hostingController.view.layoutSubtreeIfNeeded()
        let size = hostingController.view.fittingSize

        // Anchor centered under the icon, clamped onto the icon's display.
        let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        var x = buttonRect.midX - size.width / 2
        x = max(visible.minX + 8, min(x, visible.maxX - size.width - 8))
        let y = buttonRect.minY - size.height - 6
        let target = NSRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height)

        panel.setFrame(target.offsetBy(dx: 0, dy: 8), display: false)
        panel.alphaValue = 0

        NSApp.activate(ignoringOtherApps: true)   // controls work on first click; enables resignKey dismissal
        panel.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.13
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 1
        }

        // Defer past the status button's own click cycle, which would otherwise immediately
        // un-highlight it (the click that opened the popover finishes after this method returns).
        DispatchQueue.main.async { [weak button] in button?.highlight(true) }
        isShown = true
        installHooks()
    }

    func close() {
        guard isShown else { return }
        isShown = false
        button?.highlight(false)
        removeHooks()
        let win = panel
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.08
            win.animator().alphaValue = 0
        }, completionHandler: {
            win.orderOut(nil)
            win.alphaValue = 1
        })
    }

    // MARK: Dismissal

    func windowDidResignKey(_ notification: Notification) {
        guard isShown else { return }
        // Lost focus (clicked elsewhere / switched apps / clicked the icon) → dismiss.
        ignoreOpenUntil = Date().addingTimeInterval(0.25)
        close()
    }

    private func installHooks() {
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 { self?.close(); return nil }   // Esc
            return event
        }
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
    }

    private func removeHooks() {
        if let escMonitor { NSEvent.removeMonitor(escMonitor) }
        escMonitor = nil
        if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
        spaceObserver = nil
    }
}
