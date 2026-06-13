import AppKit
import Combine
import SwiftUI

/// Owns the floating shelf panel and the global drag-watcher that pops it open when you start
/// dragging files. The panel is a drop target (drag files in) and its rows are drag sources
/// (drag files back out).
@MainActor
final class ShelfController: NSObject, NSWindowDelegate {
    let store = ShelfStore()

    private(set) var corner: ShelfCorner = .topRight
    private(set) var autoPop = true
    private var defaultsPrefix = "module.shelf"

    private var panel: NSPanel?
    private var downMonitor: Any?
    private var dragMonitor: Any?
    private var upMonitor: Any?
    private var hideWorkItem: DispatchWorkItem?
    private var storeCancellable: AnyCancellable?
    private var active = false
    private var baselineDragChangeCount = 0
    private var poppedThisGesture = false
    /// True when the panel was auto-popped by a drag and nothing has been dropped yet, so an
    /// empty shelf can tuck itself away when the drag ends.
    private var autoShown = false

    // MARK: Settings

    func loadSettings(defaultsKeyPrefix: String) {
        defaultsPrefix = defaultsKeyPrefix
        let d = UserDefaults.standard
        if let raw = d.string(forKey: "\(defaultsPrefix).corner"), let c = ShelfCorner(rawValue: raw) { corner = c }
        autoPop = d.object(forKey: "\(defaultsPrefix).autoPop") as? Bool ?? true
    }

    func setCorner(_ c: ShelfCorner) {
        corner = c
        UserDefaults.standard.set(c.rawValue, forKey: "\(defaultsPrefix).corner")
        if panel?.isVisible == true { positionPanel() }
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
            if !items.isEmpty { self?.autoShown = false }   // shelf now has content → keep it sticky
        }
    }

    func stop() {
        active = false
        removeMonitors()
        storeCancellable = nil
        hidePanel()
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
        // Snapshot the drag pasteboard's change count before any drag session can start.
        baselineDragChangeCount = NSPasteboard(name: .drag).changeCount
        poppedThisGesture = false
    }

    private func handleDrag() {
        guard active, autoPop, !poppedThisGesture, panel?.isVisible != true else { return }
        // A real drag-and-drop session bumps the drag pasteboard's change count after mouse-down;
        // plain window-dragging or text selection does not. This is what distinguishes "the user is
        // dragging files" from "the user is dragging something else" without false pops from stale data.
        let current = NSPasteboard(name: .drag).changeCount
        guard current != baselineDragChangeCount, dragHasFiles() else { return }
        poppedThisGesture = true
        autoShown = true
        showPanel()
    }

    private func handleMouseUp() {
        guard active else { return }
        poppedThisGesture = false
        if autoShown, store.isEmpty, panel?.isVisible == true {
            scheduleAutoHide()
        }
    }

    private func dragHasFiles() -> Bool {
        guard let types = NSPasteboard(name: .drag).types else { return false }
        return types.contains(.fileURL)
            || types.contains(NSPasteboard.PasteboardType("NSFilenamesPboardType"))
    }

    // MARK: Panel

    /// Open the shelf. `forceVisible` marks it as a deliberate (sticky) open rather than an auto-pop.
    func openShelf(forceVisible: Bool) {
        if forceVisible { autoShown = false }
        showPanel()
    }

    private func showPanel() {
        hideWorkItem?.cancel()
        let panel = ensurePanel()
        positionPanel()
        panel.orderFrontRegardless()
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 250, height: 340),
            styleMask: [.titled, .closable, .nonactivatingPanel, .utilityWindow, .hudWindow],
            backing: .buffered,
            defer: false
        )
        p.title = "Shelf"
        p.isFloatingPanel = true
        p.level = .floating
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        p.isReleasedWhenClosed = false
        p.contentViewController = NSHostingController(
            rootView: ShelfPanelView(
                store: store,
                onClear: { [weak self] in self?.store.clear() },
                onClose: { [weak self] in self?.hidePanel() }
            )
        )
        p.delegate = self
        panel = p
        return p
    }

    private func positionPanel() {
        guard let panel, let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        let size = panel.frame.size
        let margin: CGFloat = 16
        let origin: CGPoint
        switch corner {
        case .topRight:    origin = CGPoint(x: vf.maxX - size.width - margin, y: vf.maxY - size.height - margin)
        case .topLeft:     origin = CGPoint(x: vf.minX + margin,               y: vf.maxY - size.height - margin)
        case .bottomRight: origin = CGPoint(x: vf.maxX - size.width - margin, y: vf.minY + margin)
        case .bottomLeft:  origin = CGPoint(x: vf.minX + margin,               y: vf.minY + margin)
        }
        panel.setFrameOrigin(origin)
    }

    private func hidePanel() {
        hideWorkItem?.cancel()
        panel?.orderOut(nil)
    }

    private func scheduleAutoHide() {
        hideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.store.isEmpty else { return }
            self.hidePanel()
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    // MARK: NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hidePanel()
        return false   // hide, don't destroy
    }
}
