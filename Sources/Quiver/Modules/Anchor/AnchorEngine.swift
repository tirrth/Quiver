import AppKit
import ApplicationServices

// Private AX SPI used by window managers (Rectangle, yabai, …) to read a window's CGWindowID — the
// only reliable way to tell whether two AXUIElement references point at the same window, since
// CFEqual on freshly-copied elements is unreliable.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ identifier: UnsafeMutablePointer<CGWindowID>) -> Int32

/// Moves and resizes a target app's focused window via the Accessibility API. Pure Swift; relies on
/// the same Accessibility permission Follow Focus uses.
@MainActor
final class AnchorEngine {

    // Cycle state: repeating the same edge-half on the same window steps through ½ → ⅔ → ⅓.
    private var lastWindowID: CGWindowID?
    private var lastAction: WindowAction?
    private var cycleStep = 0

    // Pre-snap frame per window, so `restore` can put it back.
    private var savedFrames: [CGWindowID: CGRect] = [:]

    /// Arrange `app`'s focused window per `action`, keeping a `gap` margin. Beeps if there's no
    /// usable window (e.g. the app has none focused, or it refuses Accessibility).
    func arrange(_ action: WindowAction, gap: CGFloat, app: NSRunningApplication?) {
        guard let app else { NSSound.beep(); return }
        guard let window = focusedWindow(of: app.processIdentifier),
              let current = appKitFrame(of: window),
              let screen = screenContaining(current) ?? NSScreen.main else { NSSound.beep(); return }
        let wid = windowID(of: window)

        switch action {
        case .restore:
            if let wid, let saved = savedFrames[wid] {
                setFrame(saved, for: window)
                savedFrames[wid] = nil
            } else {
                NSSound.beep()
            }
            lastAction = nil   // break the size cycle

        case .previousDisplay, .nextDisplay:
            moveToAdjacentDisplay(window, current: current, from: screen, forward: action == .nextDisplay)
            lastAction = nil

        default:
            if let wid, savedFrames[wid] == nil { savedFrames[wid] = current }   // remember pre-snap frame
            let fraction = nextFraction(for: action, wid: wid)
            setFrame(action.frame(in: screen.visibleFrame, gap: gap, fraction: fraction), for: window)
        }
    }

    /// Snap a specific window (used by drag-to-edge) to `action` on `screen`, remembering its
    /// pre-snap frame so `restore` can put it back.
    func snap(_ window: AXUIElement, to action: WindowAction, on screen: NSScreen, gap: CGFloat) {
        if let wid = windowID(of: window), savedFrames[wid] == nil, let current = appKitFrame(of: window) {
            savedFrames[wid] = current
        }
        setFrame(action.frame(in: screen.visibleFrame, gap: gap), for: window)
        lastAction = nil
    }

    /// Advance the ½ → ⅔ → ⅓ cycle when the same edge-half is repeated on the same window.
    private func nextFraction(for action: WindowAction, wid: CGWindowID?) -> CGFloat {
        guard action.isCyclable else {
            lastAction = action; lastWindowID = wid; cycleStep = 0
            return 0.5
        }
        let sameWindow = wid != nil && wid == lastWindowID
        cycleStep = (lastAction == action && sameWindow) ? (cycleStep + 1) % WindowAction.cycleFractions.count : 0
        lastAction = action; lastWindowID = wid
        return WindowAction.cycleFractions[cycleStep]
    }

    /// Move the window to the screen left/right of its current one, keeping its relative position/size.
    private func moveToAdjacentDisplay(_ window: AXUIElement, current: CGRect, from screen: NSScreen, forward: Bool) {
        let screens = NSScreen.screens.sorted { $0.frame.minX < $1.frame.minX }
        guard screens.count > 1, let idx = screens.firstIndex(of: screen) else { NSSound.beep(); return }
        let target = screens[(idx + (forward ? 1 : screens.count - 1)) % screens.count]
        let from = screen.visibleFrame, to = target.visibleFrame
        let relX = (current.minX - from.minX) / from.width
        let relY = (current.minY - from.minY) / from.height
        let w = min(current.width / from.width, 1) * to.width
        let h = min(current.height / from.height, 1) * to.height
        setFrame(CGRect(x: to.minX + relX * to.width, y: to.minY + relY * to.height, width: w, height: h), for: window)
    }

    private func windowID(of window: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(window, &id) == 0 ? id : nil
    }

    // MARK: AX plumbing

    private func focusedWindow(of pid: pid_t) -> AXUIElement? {
        let appEl = AXUIElementCreateApplication(pid)
        for attr in [kAXFocusedWindowAttribute, kAXMainWindowAttribute] {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(appEl, attr as CFString, &value) == .success, let value {
                return (value as! AXUIElement)
            }
        }
        return nil
    }

    /// The window's current frame in AppKit (bottom-left origin) coordinates.
    private func appKitFrame(of window: AXUIElement) -> CGRect? {
        var posVal: CFTypeRef?
        var sizeVal: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posVal) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeVal) == .success,
              let posVal, let sizeVal else { return nil }
        var pos = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posVal as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)
        return CGRect(origin: flipY(pos, height: size.height), size: size)
    }

    private func setFrame(_ rect: CGRect, for window: AXUIElement) {
        var size = rect.size
        var origin = flipY(rect.origin, height: rect.height)   // AppKit → AX (top-left) point
        // Set size, then position, then size again — windows that clamp to a min size or reposition
        // on resize otherwise land wrong; this is the same order Rectangle uses.
        if let v = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, v) }
        if let v = AXValueCreate(.cgPoint, &origin) { AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, v) }
        if let v = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, v) }
    }

    // MARK: Coordinate conversion
    // AX positions windows in a top-left origin space anchored to the primary display (y grows down);
    // AppKit uses a bottom-left origin (y grows up). The conversion is its own inverse.

    private var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    private func flipY(_ p: CGPoint, height: CGFloat) -> CGPoint {
        CGPoint(x: p.x, y: primaryHeight - p.y - height)
    }

    private func screenContaining(_ frame: CGRect) -> NSScreen? {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        if let hit = NSScreen.screens.first(where: { $0.frame.contains(center) }) { return hit }
        return NSScreen.screens.max { intersectionArea($0.frame, frame) < intersectionArea($1.frame, frame) }
    }

    private func intersectionArea(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let i = a.intersection(b)
        return i.isNull ? 0 : i.width * i.height
    }
}
