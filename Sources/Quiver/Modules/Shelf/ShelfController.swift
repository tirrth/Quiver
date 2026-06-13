import AppKit
import Combine
import QuartzCore
import SwiftUI

/// Owns the shelf drawer window and the global drag-watcher that slides it out when you start
/// dragging files. The drawer is a borderless, non-movable panel anchored to a screen edge, sized
/// to its contents; its tiles are native AppKit drag sources (so dragging a file out can't move
/// the window).
@MainActor
final class ShelfController: NSObject {
    let store = ShelfStore()

    private(set) var edge: ShelfEdge = .right
    private(set) var autoPop = true
    private var defaultsPrefix = "module.shelf"

    private var drawerWindow: NSPanel?
    private var downMonitor: Any?
    private var dragMonitor: Any?
    private var upMonitor: Any?
    private var hideWorkItem: DispatchWorkItem?
    private var storeCancellable: AnyCancellable?
    private var active = false
    private var baselineDragChangeCount = 0
    private var poppedThisGesture = false
    private var autoShown = false

    // MARK: Settings

    func loadSettings(defaultsKeyPrefix: String) {
        defaultsPrefix = defaultsKeyPrefix
        let d = UserDefaults.standard
        if let raw = d.string(forKey: "\(defaultsPrefix).edge"), let e = ShelfEdge(rawValue: raw) { edge = e }
        autoPop = d.object(forKey: "\(defaultsPrefix).autoPop") as? Bool ?? true
    }

    func setEdge(_ e: ShelfEdge) {
        edge = e
        UserDefaults.standard.set(e.rawValue, forKey: "\(defaultsPrefix).edge")
        // Column count/width depend on the edge, so rebuild the window with the new layout.
        let wasVisible = drawerWindow?.isVisible == true
        drawerWindow?.orderOut(nil)
        drawerWindow = nil
        if wasVisible { showDrawer() }
    }

    func setAutoPop(_ value: Bool) {
        autoPop = value
        UserDefaults.standard.set(value, forKey: "\(defaultsPrefix).autoPop")
    }

    // MARK: Lifecycle

    func start() {
        active = true
        installMonitors()
        storeCancellable = store.$items.sink { [weak self] items in
            guard let self else { return }
            if !items.isEmpty { self.autoShown = false }   // shelf has content → keep it sticky
            self.relayoutIfVisible()
        }
    }

    func stop() {
        active = false
        removeMonitors()
        storeCancellable = nil
        hideDrawer(animated: false)
        store.clear()
    }

    private func installMonitors() {
        // Global monitors for mouse events don't require any permission.
        if downMonitor == nil {
            downMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
                self?.handleMouseDown()
            }
        }
        if dragMonitor == nil {
            dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] _ in
                self?.handleDrag()
            }
        }
        if upMonitor == nil {
            upMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
                self?.handleMouseUp()
            }
        }
    }

    private func removeMonitors() {
        for monitor in [downMonitor, dragMonitor, upMonitor].compactMap({ $0 }) {
            NSEvent.removeMonitor(monitor)
        }
        downMonitor = nil
        dragMonitor = nil
        upMonitor = nil
    }

    // MARK: Drag detection

    private func handleMouseDown() {
        baselineDragChangeCount = NSPasteboard(name: .drag).changeCount
        poppedThisGesture = false
    }

    private func handleDrag() {
        guard active, autoPop, !poppedThisGesture, drawerWindow?.isVisible != true else { return }
        // A real drag-and-drop session bumps the drag pasteboard's change count after mouse-down;
        // plain window-dragging or text selection does not — this avoids false pops.
        let current = NSPasteboard(name: .drag).changeCount
        guard current != baselineDragChangeCount, dragHasFiles() else { return }
        poppedThisGesture = true
        autoShown = true
        showDrawer()
    }

    private func handleMouseUp() {
        guard active else { return }
        poppedThisGesture = false
        if autoShown, store.isEmpty, drawerWindow?.isVisible == true {
            scheduleAutoHide()
        }
    }

    private func dragHasFiles() -> Bool {
        guard let types = NSPasteboard(name: .drag).types else { return false }
        return types.contains(.fileURL)
            || types.contains(NSPasteboard.PasteboardType("NSFilenamesPboardType"))
    }

    // MARK: Show / hide

    func openShelf(forceVisible: Bool) {
        if forceVisible { autoShown = false }
        showDrawer()
    }

    private func showDrawer() {
        hideWorkItem?.cancel()
        let screen = screenUnderMouse()
        let size = ShelfMetrics.windowSize(itemCount: store.count, edge: edge, maxHeight: screen.visibleFrame.height * 0.8)
        let onFrame = drawerFrame(on: screen, edge: edge, size: size)
        let window = ensureWindow()

        if window.isVisible {
            window.setFrame(onFrame, display: true, animate: true)
            return
        }

        let offFrame = offscreenFrame(from: onFrame, edge: edge)
        window.setFrame(offFrame, display: false)
        window.alphaValue = 0
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.18, 0.9, 0.2, 1) // snappy ease-out
            window.animator().setFrame(onFrame, display: true)
            window.animator().alphaValue = 1
        }
    }

    func hideDrawer(animated: Bool = true) {
        hideWorkItem?.cancel()
        guard let window = drawerWindow, window.isVisible else { return }
        guard animated else { window.orderOut(nil); return }

        let offFrame = offscreenFrame(from: window.frame, edge: edge)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().setFrame(offFrame, display: true)
            window.animator().alphaValue = 0
        }, completionHandler: {
            window.orderOut(nil)
            window.alphaValue = 1
        })
    }

    /// Re-size and re-anchor the drawer to fit its contents (called as items are added/removed).
    private func relayoutIfVisible() {
        guard let window = drawerWindow, window.isVisible else { return }
        let screen = window.screen ?? screenUnderMouse()
        let size = ShelfMetrics.windowSize(itemCount: store.count, edge: edge, maxHeight: screen.visibleFrame.height * 0.8)
        let onFrame = drawerFrame(on: screen, edge: edge, size: size)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(onFrame, display: true)
        }
    }

    private func scheduleAutoHide() {
        hideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.store.isEmpty else { return }
            self.hideDrawer()
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    // MARK: Window + geometry

    private func ensureWindow() -> NSPanel {
        if let drawerWindow { return drawerWindow }
        let initial = ShelfMetrics.windowSize(itemCount: 0, edge: edge, maxHeight: 800)
        let window = NSPanel(
            contentRect: NSRect(origin: .zero, size: initial),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isMovable = false
        window.isMovableByWindowBackground = false
        window.level = .floating
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.isReleasedWhenClosed = false

        let host = NSHostingController(
            rootView: ShelfDrawerContent(
                store: store,
                edge: edge,
                columns: ShelfMetrics.columns(for: edge),
                onClear: { [weak self] in self?.store.clear() },
                onClose: { [weak self] in self?.hideDrawer() }
            )
        )
        host.view.wantsLayer = true
        host.view.layer?.backgroundColor = NSColor.clear.cgColor
        window.contentViewController = host
        drawerWindow = window
        return window
    }

    private func screenUnderMouse() -> NSScreen {
        let loc = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(loc, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    private func drawerFrame(on screen: NSScreen, edge: ShelfEdge, size: NSSize) -> NSRect {
        let vf = screen.visibleFrame
        // Flush against the edge so it reads as "attached" / sliding out of the screen side.
        switch edge {
        case .right:  return NSRect(x: vf.maxX - size.width, y: vf.midY - size.height / 2, width: size.width, height: size.height)
        case .left:   return NSRect(x: vf.minX,              y: vf.midY - size.height / 2, width: size.width, height: size.height)
        case .top:    return NSRect(x: vf.midX - size.width / 2, y: vf.maxY - size.height, width: size.width, height: size.height)
        case .bottom: return NSRect(x: vf.midX - size.width / 2, y: vf.minY,               width: size.width, height: size.height)
        }
    }

    private func offscreenFrame(from frame: NSRect, edge: ShelfEdge) -> NSRect {
        let pad: CGFloat = 24
        switch edge {
        case .right:  return frame.offsetBy(dx: frame.width + pad, dy: 0)
        case .left:   return frame.offsetBy(dx: -(frame.width + pad), dy: 0)
        case .top:    return frame.offsetBy(dx: 0, dy: frame.height + pad)
        case .bottom: return frame.offsetBy(dx: 0, dy: -(frame.height + pad))
        }
    }
}
