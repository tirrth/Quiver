import AppKit
import ApplicationServices

/// Watches global mouse drags via a `CGEventTap` and, when a window is dragged to a screen edge or
/// corner, previews the snapped frame and applies it on release. macOS exposes no public
/// "window dragged" callback, so — like Rectangle/Magnet/Loop — we tap mouse events (Accessibility
/// gated, already granted) and detect a genuine window drag by watching the window's position move.
@MainActor
final class DragSnapController {
    private let engine: AnchorEngine
    private let gapProvider: () -> CGFloat
    private let topEdgeFullScreen: () -> Bool

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let preview = SnapPreviewWindow()

    // Drag state.
    private var candidate: AXUIElement?     // window under the cursor at mouse-down
    private var downOrigin: CGPoint?        // its position then (AX coords; only used for a move delta)
    private var active = false              // confirmed a real window drag
    private var currentZone: WindowAction?
    private var currentScreen: NSScreen?

    private let edgeThreshold: CGFloat = 16   // distance from a screen edge that triggers a zone
    private let cornerBand: CGFloat = 130     // how far along the edges the corner zones reach
    private let moveThreshold: CGFloat = 4    // window must move this far to count as a drag

    init(engine: AnchorEngine, gap: @escaping () -> CGFloat, topEdgeFullScreen: @escaping () -> Bool) {
        self.engine = engine
        self.gapProvider = gap
        self.topEdgeFullScreen = topEdgeFullScreen
    }

    var isRunning: Bool { tap != nil }

    func start() {
        guard tap == nil else { return }
        let mask: CGEventMask =
            (1 << UInt64(CGEventType.leftMouseDown.rawValue)) |
            (1 << UInt64(CGEventType.leftMouseDragged.rawValue)) |
            (1 << UInt64(CGEventType.leftMouseUp.rawValue))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                if let userInfo {
                    let c = Unmanaged<DragSnapController>.fromOpaque(userInfo).takeUnretainedValue()
                    MainActor.assumeIsolated { c.handle(type: type, event: event) }
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: selfPtr
        ) else { Log.error("Anchor: could not create the drag-snap event tap"); return }

        self.tap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        runLoopSource = nil
        tap = nil
        reset()
    }

    private func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }   // re-arm if the system disabled us
        case .leftMouseDown:
            candidate = windowUnderCursor(at: event.location)
            downOrigin = candidate.flatMap(rawOrigin(of:))
            active = false
            currentZone = nil
            currentScreen = nil
        case .leftMouseDragged:
            handleDrag()
        case .leftMouseUp:
            handleUp()
        default:
            break
        }
    }

    private func handleDrag() {
        guard let candidate, let downOrigin else { return }
        if !active {
            // Only treat it as a window drag once the window has actually moved (skips text selection).
            guard let now = rawOrigin(of: candidate),
                  abs(now.x - downOrigin.x) > moveThreshold || abs(now.y - downOrigin.y) > moveThreshold
            else { return }
            active = true
        }

        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else {
            hidePreview(); return
        }
        let newZone = zone(for: mouse, on: screen)
        guard newZone != currentZone || screen != currentScreen else { return }
        currentZone = newZone
        currentScreen = screen
        if let newZone {
            // Full screen covers the whole display, so preview the full frame rather than the inset one.
            let frame = newZone == .fullScreen ? screen.frame : newZone.frame(in: screen.visibleFrame, gap: gapProvider())
            preview.show(frame: frame)
        } else {
            hidePreview()
        }
    }

    private func handleUp() {
        defer { reset() }
        guard active, let candidate, let zone = currentZone, let screen = currentScreen else { return }
        engine.snap(candidate, to: zone, on: screen, gap: gapProvider())
    }

    private func reset() {
        candidate = nil
        downOrigin = nil
        active = false
        currentZone = nil
        currentScreen = nil
        hidePreview()
    }

    private func hidePreview() { preview.hide() }

    // MARK: Zone detection (AppKit / bottom-left coordinates)

    private func zone(for m: CGPoint, on screen: NSScreen) -> WindowAction? {
        let f = screen.frame
        let e = edgeThreshold, c = cornerBand
        let nearL = m.x <= f.minX + e, nearR = m.x >= f.maxX - e
        let nearT = m.y >= f.maxY - e, nearB = m.y <= f.minY + e
        guard nearL || nearR || nearT || nearB else { return nil }
        let topBand = m.y >= f.maxY - c, bottomBand = m.y <= f.minY + c
        let leftBand = m.x <= f.minX + c, rightBand = m.x >= f.maxX - c
        if (nearL && topBand) || (nearT && leftBand) { return .topLeft }
        if (nearR && topBand) || (nearT && rightBand) { return .topRight }
        if (nearL && bottomBand) || (nearB && leftBand) { return .bottomLeft }
        if (nearR && bottomBand) || (nearB && rightBand) { return .bottomRight }
        if nearL { return .leftHalf }
        if nearR { return .rightHalf }
        // Top edge → native full screen, unless double-click already handles full screen, in which
        // case the drag does a windowed maximize instead.
        if nearT { return topEdgeFullScreen() ? .fullScreen : .maximize }
        if nearB { return .bottomHalf }
        return nil
    }

    // MARK: AX helpers

    private func windowUnderCursor(at point: CGPoint) -> AXUIElement? {
        let sys = AXUIElementCreateSystemWide()
        var el: AXUIElement?
        guard AXUIElementCopyElementAtPosition(sys, Float(point.x), Float(point.y), &el) == .success, let el else {
            return nil
        }
        return windowAncestor(of: el)
    }

    private func windowAncestor(of element: AXUIElement, depth: Int = 0) -> AXUIElement? {
        guard depth < 8 else { return nil }
        var role: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success,
           (role as? String) == (kAXWindowRole as String) {
            return element
        }
        var win: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &win) == .success, let win {
            return (win as! AXUIElement)
        }
        var parent: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parent) == .success, let parent {
            return windowAncestor(of: parent as! AXUIElement, depth: depth + 1)
        }
        return nil
    }

    /// The window's origin (AX top-left coords); only used to detect movement, so the space is moot.
    private func rawOrigin(of window: AXUIElement) -> CGPoint? {
        var posVal: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posVal) == .success,
              let posVal else { return nil }
        var pos = CGPoint.zero
        AXValueGetValue(posVal as! AXValue, .cgPoint, &pos)
        return pos
    }
}
