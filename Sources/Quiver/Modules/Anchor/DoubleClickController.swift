import AppKit
import ApplicationServices

/// Makes a double-click on a window's title bar toggle native full screen. Uses a *consuming* event
/// tap so macOS's own double-click action (zoom/minimize) doesn't also fire. To keep latency and
/// risk minimal, only the second click of a double-click ever does an Accessibility lookup; every
/// other mouse event passes straight through untouched.
@MainActor
final class DoubleClickController {
    private let engine: AnchorEngine
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var swallowUp = false

    init(engine: AnchorEngine) { self.engine = engine }

    var isRunning: Bool { tap != nil }

    func start() {
        guard tap == nil else { return }
        let mask: CGEventMask =
            (1 << UInt64(CGEventType.leftMouseDown.rawValue)) |
            (1 << UInt64(CGEventType.leftMouseUp.rawValue))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let c = Unmanaged<DoubleClickController>.fromOpaque(userInfo).takeUnretainedValue()
                return MainActor.assumeIsolated { c.handle(type: type, event: event) }
            },
            userInfo: selfPtr
        ) else { Log.error("Anchor: could not create the double-click event tap"); return }

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
        swallowUp = false
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        case .leftMouseDown:
            // Fast path: only the second click of a double-click is interesting.
            guard event.getIntegerValueField(.mouseEventClickState) == 2,
                  let window = titleBarWindow(at: event.location) else { return pass }
            engine.toggleFullScreen(window)
            swallowUp = true
            return nil   // consume so macOS's native double-click action doesn't also fire
        case .leftMouseUp:
            if swallowUp { swallowUp = false; return nil }
            return pass
        default:
            return pass
        }
    }

    /// Returns the window if `point` (global, top-left) is on its draggable title-bar/toolbar band
    /// and not on an interactive control, else nil.
    private func titleBarWindow(at point: CGPoint) -> AXUIElement? {
        let sys = AXUIElementCreateSystemWide()
        var el: AXUIElement?
        guard AXUIElementCopyElementAtPosition(sys, Float(point.x), Float(point.y), &el) == .success, let el else {
            return nil
        }
        // Never hijack clicks on interactive controls (traffic lights, toolbar buttons, fields, …).
        if let r = role(of: el), Self.controlRoles.contains(r) { return nil }
        guard let window = windowAncestor(of: el), let frame = axFrame(of: window) else { return nil }
        // The click must land within the title-bar band (extended to cover an integrated toolbar).
        guard point.y >= frame.minY, point.y <= frame.minY + titleBarBand(of: window, windowTop: frame.minY) else {
            return nil
        }
        return window
    }

    private static let controlRoles: Set<String> = [
        "AXButton", "AXMenuButton", "AXPopUpButton", "AXMenuItem", "AXTextField", "AXTextArea",
        "AXComboBox", "AXSlider", "AXCheckBox", "AXRadioButton", "AXIncrementor", "AXStepper",
        "AXDisclosureTriangle", "AXLink", "AXSearchField", "AXSegmentedControl"
    ]

    private func role(of element: AXUIElement) -> String? {
        var r: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &r) == .success else { return nil }
        return r as? String
    }

    private func axFrame(of element: AXUIElement) -> CGRect? {
        var posVal: CFTypeRef?
        var sizeVal: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posVal) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeVal) == .success,
              let posVal, let sizeVal else { return nil }
        var p = CGPoint.zero
        var s = CGSize.zero
        AXValueGetValue(posVal as! AXValue, .cgPoint, &p)
        AXValueGetValue(sizeVal as! AXValue, .cgSize, &s)
        return CGRect(origin: p, size: s)
    }

    private func windowAncestor(of element: AXUIElement, depth: Int = 0) -> AXUIElement? {
        guard depth < 10 else { return nil }
        if role(of: element) == "AXWindow" { return element }
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

    /// Height of the draggable title-bar region, extended to cover an integrated toolbar if present.
    private func titleBarBand(of window: AXUIElement, windowTop: CGFloat) -> CGFloat {
        let standard: CGFloat = 30
        var childrenVal: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXChildrenAttribute as CFString, &childrenVal) == .success,
              let children = childrenVal as? [AXUIElement] else { return standard }
        for child in children where role(of: child) == "AXToolbar" {
            if let tf = axFrame(of: child) { return max(standard, tf.maxY - windowTop) }
        }
        return standard
    }
}
