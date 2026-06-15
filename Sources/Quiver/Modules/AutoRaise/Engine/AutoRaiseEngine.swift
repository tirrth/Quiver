/*
 * AutoRaise engine — a Swift port of AutoRaise by sbmpost (https://github.com/sbmpost/AutoRaise),
 * which is licensed under the GNU General Public License v2 or later. Some pieces are based on
 * metamove by jmgao (part of XFree86) and on focus-only methods from yabai by koekeishiya.
 *
 * This file is a faithful, behaviour-preserving translation of AutoRaise.mm into Swift. The focus
 * and raise heuristics, timings, corrections and ordering are kept identical to the original; only
 * the language and the (ARC-based) memory management differ.
 *
 * As a derivative of GPL'd code, Quiver as a whole is distributed under the GPL when distributed.
 */

import AppKit
import ApplicationServices
import Carbon
import Darwin

// MARK: - Private / undocumented system SPIs
//
// These are undocumented and subject to incompatible changes. They are bound by symbol name via
// @_silgen_name (the same approach AutoRaise used through `extern "C"`). They live in the SkyLight
// private framework / the AX subsystem, linked by build.sh.

@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> Int32

@_silgen_name("CGSSetCursorScale")
private func CGSSetCursorScale(_ connectionId: Int32, _ scale: Float) -> CGError

@_silgen_name("CGSGetCursorScale")
private func CGSGetCursorScale(_ connectionId: Int32, _ scale: UnsafeMutablePointer<Float>) -> CGError

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError

// The Carbon Process Manager APIs are no longer surfaced by the Swift overlay (marked unavailable),
// but the symbols still exist. Bind them directly so AutoRaise's activation paths keep working.
private let kSetFrontProcessFrontWindowOnly: UInt32 = 1   // (1 << 0)

@_silgen_name("GetProcessForPID")
private func ar_GetProcessForPID(_ pid: pid_t, _ psn: UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus

@_silgen_name("SetFrontProcessWithOptions")
private func ar_SetFrontProcessWithOptions(_ psn: UnsafePointer<ProcessSerialNumber>, _ options: UInt32) -> OSStatus

@_silgen_name("SameProcess")
private func ar_SameProcess(_ psn1: UnsafePointer<ProcessSerialNumber>, _ psn2: UnsafePointer<ProcessSerialNumber>, _ result: UnsafeMutablePointer<DarwinBoolean>) -> OSStatus

#if FOCUS_FIRST
@_silgen_name("SLPSPostEventRecordTo")
private func SLPSPostEventRecordTo(_ psn: UnsafeMutablePointer<ProcessSerialNumber>, _ bytes: UnsafeMutablePointer<UInt8>) -> CGError

@_silgen_name("_SLPSSetFrontProcessWithOptions")
private func _SLPSSetFrontProcessWithOptions(_ psn: UnsafeMutablePointer<ProcessSerialNumber>, _ wid: UInt32, _ mode: UInt32) -> CGError
#endif

// MARK: - Constants

private let AUTORAISE_VERSION = "5.6"
private let STACK_THRESHOLD = 20

// OSX Monterey introduced a transparent 3px border around each window; correct the mouse position
// before determining which window is underneath it (see AutoRaise.mm for the full rationale).
private let WINDOW_CORRECTION: CGFloat = 3
private let MENUBAR_CORRECTION: CGFloat = 8
private let SCREEN_EDGE_CORRECTION: CGFloat = 1

private let ACTIVATE_DELAY_MS = 10
private let SCALE_DELAY_MS = 400
private let SCALE_DURATION_MS = SCALE_DELAY_MS + 600
private let TASK_SWITCHER_MODIFIER_KEY: CGEventFlags = .maskCommand

#if FOCUS_FIRST
private let kCPSUserGenerated: UInt32 = 0x200
#endif

private let mainWindowAppsWithoutTitle = [
    "System Settings", "System Information", "Photos", "Calculator", "Podcasts", "Stickies Pro", "Reeder"
]
private let pwas = ["Chrome", "Chromium", "Vivaldi", "Brave", "Opera", "edgemac", "helium"]
private let AppsRaisingOnFocus = ["IntelliJ IDEA", "PyCharm", "WebStorm", "Arc", "Dia"]
private let DockBundleId = "com.apple.dock"
private let FinderBundleId = "com.apple.finder"
private let AssistiveControl = "AssistiveControl"
private let MissionControl = "Mission Control"
private let BartenderBar = "Bartender Bar"
private let AppStoreSearchResults = "Search results"
private let Untitled = "Untitled"   // OSX Email search
private let Zim = "Zim"
private let XQuartz = "XQuartz"
private let Finder = "Finder"
private let Pake = "pake"
private let NoTitle = ""

// MARK: - Engine state (process-global, mirrors AutoRaise.mm statics)

private let systemWideElement = AXUIElementCreateSystemWide()

private var axObserver: AXObserver?
private var lastDestroyedMouseWindow_id: UInt64 = 0
private var eventTap: CFMachPort?
private var eventTapRunLoopSource: CFRunLoopSource?
private var activated_by_task_switcher = false
private var _previousFinderWindow: AXUIElement?
private var _dock_app: AXUIElement?
private var ignoreApps: [String]?
private var ignoreTitles: [String]?
private var stayFocusedBundleIds: [String]?
private var desktopOrigin: CGPoint = .zero
private var oldPoint: CGPoint = .zero
private var oldCorrectedPoint: CGPoint = .zero
private var propagateMouseMoved = false
private var requireMouseStop = true
private var ignoreSpaceChanged = false
private var invertDisableKey = false
private var invertIgnoreApps = false
private var spaceHasChanged = false
private var appWasActivated = false
private var altTaskSwitcher = false
private var warpMouse = false
private var verbose = false
private var warpX: Float = 0.5
private var warpY: Float = 0.5
private var oldScale: Float = 1
private var cursorScale: Float = 2
private var mouseDelta: Float = 0
private var ignoreTimes = 0
private var raiseTimes = 0
private var delayTicks = 0
private var delayCount = 0
private var pollMillis = 0
private var disableKey: CGEventFlags = []
private var engineActive = false
private var workspaceWatcher: MDWorkspaceWatcher?

// Replacements for function-local `static` variables in the original (persist across ticks).
private var onTick_previous_id: CGWindowID = 0
private var commandTabPressed = false
private var commandGravePressed = false

#if FOCUS_FIRST
private var raiseDelayCount = 0
private var lastFocusedWindow_pid: pid_t = 0
private var _lastFocusedWindow: AXUIElement?
#endif

// MARK: - AX helpers (ARC-managed; no manual CFRelease)

/// Copies an accessibility attribute, returning an ARC-managed value (or nil on any error).
private func axCopy(_ element: AXUIElement, _ attribute: CFString) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, attribute, &value) == .success ? value : nil
}

private func axCopyElement(_ element: AXUIElement, _ attribute: CFString) -> AXUIElement? {
    guard let value = axCopy(element, attribute) else { return nil }
    return (value as! AXUIElement)
}

private func windowID(_ element: AXUIElement) -> CGWindowID {
    var id: CGWindowID = 0
    return _AXUIElementGetWindow(element, &id) == .success ? id : 0
}

// MARK: - focus-only methods (from yabai, see AutoRaise.mm)

#if FOCUS_FIRST
private func writeUInt32(_ buffer: inout [UInt8], at offset: Int, _ value: UInt32) {
    var v = value
    withUnsafeBytes(of: &v) { src in
        for i in 0..<4 { buffer[offset + i] = src[i] }
    }
}

private func window_manager_make_key_window(_ windowPsn: inout ProcessSerialNumber, _ windowId: UInt32) {
    var bytes = [UInt8](repeating: 0, count: 0xf8)
    bytes[0x04] = 0xf8
    bytes[0x3a] = 0x10
    writeUInt32(&bytes, at: 0x3c, windowId)
    for i in 0x20..<0x30 { bytes[i] = 0xFF }

    bytes[0x08] = 0x01
    bytes.withUnsafeMutableBufferPointer { _ = SLPSPostEventRecordTo(&windowPsn, $0.baseAddress!) }

    bytes[0x08] = 0x02
    bytes.withUnsafeMutableBufferPointer { _ = SLPSPostEventRecordTo(&windowPsn, $0.baseAddress!) }
}

private func window_manager_focus_window_without_raise(
    _ windowPsn: inout ProcessSerialNumber, _ windowId: UInt32,
    _ focusedPsn: UnsafeMutablePointer<ProcessSerialNumber>?, _ focusedWindowId: UInt32
) {
    if verbose { NSLog("Focus") }
    if let focusedPsn {
        var sameProcess: DarwinBoolean = false
        _ = ar_SameProcess(&windowPsn, focusedPsn, &sameProcess)
        if sameProcess.boolValue {
            if verbose { NSLog("Same process") }
            var bytes = [UInt8](repeating: 0, count: 0xf8)
            bytes[0x04] = 0xf8
            bytes[0x08] = 0x0d

            bytes[0x8a] = 0x02
            writeUInt32(&bytes, at: 0x3c, focusedWindowId)
            bytes.withUnsafeMutableBufferPointer { _ = SLPSPostEventRecordTo(focusedPsn, $0.baseAddress!) }

            // @hack: artificially delay the activation by 1ms; some apps get confused if both
            // events appear instantaneously.
            usleep(10000)

            bytes[0x8a] = 0x01
            writeUInt32(&bytes, at: 0x3c, windowId)
            bytes.withUnsafeMutableBufferPointer { _ = SLPSPostEventRecordTo(&windowPsn, $0.baseAddress!) }
        }
    }

    _ = _SLPSSetFrontProcessWithOptions(&windowPsn, windowId, kCPSUserGenerated)
    window_manager_make_key_window(&windowPsn, windowId)
}
#endif

// MARK: - helper methods

private func activate(_ pid: pid_t) {
    if verbose { NSLog("Activate") }
#if OLD_ACTIVATION_METHOD
    var process = ProcessSerialNumber()
    if ar_GetProcessForPID(pid, &process) == noErr {
        _ = ar_SetFrontProcessWithOptions(&process, kSetFrontProcessFrontWindowOnly)
    }
#else
    // Note: activate(options:) does not work properly on OSX 11.1
    NSRunningApplication(processIdentifier: pid)?.activate(options: [])
#endif
}

private func raiseAndActivate(_ window: AXUIElement, _ windowPid: pid_t) {
    if verbose { NSLog("Raise") }
    if AXUIElementPerformAction(window, kAXRaiseAction as CFString) == .success {
        activate(windowPid)
    }
}

private func logWindowTitle(_ prefix: String, _ window: AXUIElement) {
    if let titleValue = axCopy(window, kAXTitleAttribute as CFString), let title = titleValue as? String {
        NSLog("%@: `%@`", prefix, title)
    } else {
        var pid: pid_t = 0
        if AXUIElementGetPid(window, &pid) == .success,
           let name = NSRunningApplication(processIdentifier: pid)?.localizedName {
            NSLog("%@ (app name): `%@`", prefix, name)
        } else {
            NSLog("%@: null", prefix)
        }
    }
}

// TODO: does not take into account different languages
private func titleEquals(_ element: AXUIElement, _ titles: [String], _ patterns: [String]? = nil, logTitle: Bool = false) -> Bool {
    var equal = false
    let titleValue = axCopy(element, kAXTitleAttribute as CFString)
    if logTitle { NSLog("element title: `%@`", (titleValue as? String) ?? "(null)") }
    if let title = titleValue as? String {
        equal = titles.contains(title)
        if !equal, let patterns {
            for pattern in patterns {
                if title.range(of: pattern, options: .regularExpression) != nil { equal = true; break }
            }
        }
    } else {
        equal = titles.contains(NoTitle)
    }
    return equal
}

private func dock_active() -> Bool {
    guard let dock = _dock_app else { return false }
    if axCopy(dock, kAXFocusedUIElementAttribute as CFString) != nil {
        if verbose { NSLog("Dock is active") }
        return true
    }
    return false
}

private func mc_active() -> Bool {
    guard let dock = _dock_app, let childrenValue = axCopy(dock, kAXChildrenAttribute as CFString) else { return false }
    let children = childrenValue as! NSArray
    var active = false
    for case let element as AXUIElement in children {
        if active { break }
        if let roleValue = axCopy(element, kAXRoleAttribute as CFString), let role = roleValue as? String {
            active = (role == (kAXGroupRole as String)) && titleEquals(element, [MissionControl])
        }
    }
    if verbose && active { NSLog("Mission Control is active") }
    return active
}

private func topwindow(_ point: CGPoint) -> NSDictionary? {
    guard let windowList = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [NSDictionary] else { return nil }

    for window in windowList {
        let boundsDict = window[kCGWindowBounds as String] as? NSDictionary

        if !((window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0) { continue }

        let windowBounds = NSRect(
            x: (boundsDict?["X"] as? NSNumber)?.intValue ?? 0,
            y: (boundsDict?["Y"] as? NSNumber)?.intValue ?? 0,
            width: (boundsDict?["Width"] as? NSNumber)?.intValue ?? 0,
            height: (boundsDict?["Height"] as? NSNumber)?.intValue ?? 0)

        if NSPointInRect(point, windowBounds) { return window }
    }
    return nil
}

private func fallback(_ point: CGPoint) -> AXUIElement? {
    if verbose { NSLog("Fallback") }
    guard let topWindow = topwindow(point) else { return nil }
    let pid = (topWindow[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0
    let windowOwner = AXUIElementCreateApplication(pid)

    guard let windowsValue = axCopy(windowOwner, kAXWindowsAttribute as CFString) else {
        activate(pid)
        return nil
    }
    let applicationWindows = windowsValue as! NSArray
    let topWindowId = (topWindow[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0
    if topWindowId != 0 {
        for case let applicationWindow as AXUIElement in applicationWindows {
            if windowID(applicationWindow) == topWindowId {
                return applicationWindow   // ARC retains for the return
            }
        }
    }
    return nil
}

private func get_raisable_window(_ element: AXUIElement?, _ point: CGPoint, _ count: Int) -> AXUIElement? {
    guard let element else { return nil }

    if count >= STACK_THRESHOLD {
        if verbose {
            NSLog("Stack threshold reached")
            var applicationPid: pid_t = 0
            if AXUIElementGetPid(element, &applicationPid) == .success {
                var buffer = [CChar](repeating: 0, count: 4096)
                proc_pidpath(applicationPid, &buffer, UInt32(buffer.count))
                NSLog("Application path: %s", buffer)
            }
        }
        return nil
    }

    var window: AXUIElement?
    let roleValue = axCopy(element, kAXRoleAttribute as CFString)
    var checkAttributes = (roleValue == nil)
    if let role = roleValue as? String {
        switch role {
        case kAXDockItemRole, kAXMenuItemRole, kAXMenuRole, kAXMenuBarRole, kAXMenuBarItemRole:
            break   // ignore — window stays nil
        case kAXWindowRole, kAXSheetRole, kAXDrawerRole:
            window = element
        case kAXApplicationRole:
            if titleEquals(element, [XQuartz]) {
                var applicationPid: pid_t = 0
                if AXUIElementGetPid(element, &applicationPid) == .success {
                    let frontmostPid = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1
                    if applicationPid != frontmostPid {
                        // Focus and/or raising is the responsibility of XQuartz. As such AutoRaise
                        // features (delay/warp) do not apply.
                        activate(applicationPid)
                    }
                }
            } else {
                checkAttributes = true
            }
        default:
            checkAttributes = true
        }
    }

    if checkAttributes {
        let parent = axCopyElement(element, kAXParentAttribute as CFString)
        let noParent = (parent == nil)
        window = get_raisable_window(parent, point, count + 1)
        if window == nil {
            window = axCopyElement(element, kAXWindowAttribute as CFString)
            if window == nil && noParent { window = fallback(point) }
        }
    }

    return window
}

private func get_mousewindow(_ point: CGPoint) -> AXUIElement? {
    var element: AXUIElement?
    let error = AXUIElementCopyElementAtPosition(systemWideElement, Float(point.x), Float(point.y), &element)

    var window: AXUIElement?
    if let element {
        window = get_raisable_window(element, point, 0)
    } else if error == .cannotComplete || error == .notImplemented {
        // fallback, happens for apps that do not support the Accessibility API
        if verbose { NSLog("Copy element: no accessibility support") }
        window = fallback(point)
    } else if error == .illegalArgument {
        // fallback, happens for Progressive Web Apps (PWAs)
        if verbose { NSLog("Copy element: illegal argument") }
        window = fallback(point)
    } else if error == .noValue {
        // fallback, happens sometimes when switching to another app (with cmd-tab)
        if verbose { NSLog("Copy element: no value") }
        window = fallback(point)
    } else if error == .attributeUnsupported {
        // no fallback, happens when hovering into volume/WiFi menubar window
        if verbose { NSLog("Copy element: attribute unsupported") }
    } else if error == .failure {
        // no fallback, happens when hovering over the menubar itself
        if verbose { NSLog("Copy element: failure") }
    } else if verbose {
        NSLog("Copy element: AXError %d", error.rawValue)
    }

    if verbose {
        if let window { logWindowTitle("Mouse window", window) } else { NSLog("No raisable window") }
    }

    return window
}

private func get_mousepoint(_ window: AXUIElement) -> CGPoint {
    var mousepoint = CGPoint.zero
    guard let sizeValue = axCopy(window, kAXSizeAttribute as CFString),
          let posValue = axCopy(window, kAXPositionAttribute as CFString) else { return mousepoint }
    var cgSize = CGSize.zero
    var cgPos = CGPoint.zero
    if AXValueGetValue(sizeValue as! AXValue, .cgSize, &cgSize),
       AXValueGetValue(posValue as! AXValue, .cgPoint, &cgPos) {
        mousepoint.x = cgPos.x + (cgSize.width * CGFloat(warpX))
        mousepoint.y = cgPos.y + (cgSize.height * CGFloat(warpY))
    }
    return mousepoint
}

private func contained_within(_ window1: AXUIElement, _ window2: AXUIElement) -> Bool {
    guard let size1 = axCopy(window1, kAXSizeAttribute as CFString),
          let pos1 = axCopy(window1, kAXPositionAttribute as CFString),
          let size2 = axCopy(window2, kAXSizeAttribute as CFString),
          let pos2 = axCopy(window2, kAXPositionAttribute as CFString) else { return false }
    var cgSize1 = CGSize.zero, cgSize2 = CGSize.zero, cgPos1 = CGPoint.zero, cgPos2 = CGPoint.zero
    guard AXValueGetValue(size1 as! AXValue, .cgSize, &cgSize1),
          AXValueGetValue(pos1 as! AXValue, .cgPoint, &cgPos1),
          AXValueGetValue(size2 as! AXValue, .cgSize, &cgSize2),
          AXValueGetValue(pos2 as! AXValue, .cgPoint, &cgPos2) else { return false }
    return cgPos1.x > cgPos2.x && cgPos1.y > cgPos2.y &&
        cgPos1.x + cgSize1.width < cgPos2.x + cgSize2.width &&
        cgPos1.y + cgSize1.height < cgPos2.y + cgSize2.height
}

private func findDockApplication() {
    for app in NSWorkspace.shared.runningApplications where app.bundleIdentifier == DockBundleId {
        _dock_app = AXUIElementCreateApplication(app.processIdentifier)
        break
    }
    if verbose && _dock_app == nil { NSLog("Dock application isn't running") }
}

private func findDesktopOrigin() {
    guard let mainScreen = NSScreen.screens.first else { return }
    let mainScreenTop = NSMaxY(mainScreen.frame)
    for screen in NSScreen.screens {
        let screenOriginY = mainScreenTop - NSMaxY(screen.frame)
        if screenOriginY < desktopOrigin.y { desktopOrigin.y = screenOriginY }
        if screen.frame.origin.x < desktopOrigin.x { desktopOrigin.x = screen.frame.origin.x }
    }
    if verbose { NSLog("Desktop origin (%f, %f)", desktopOrigin.x, desktopOrigin.y) }
}

private func findScreen(_ point: CGPoint) -> NSScreen? {
    guard let mainScreen = NSScreen.screens.first else { return nil }
    var p = point
    p.y = NSMaxY(mainScreen.frame) - p.y
    for screen in NSScreen.screens {
        let screenBounds = NSRect(
            x: screen.frame.origin.x, y: screen.frame.origin.y,
            width: NSWidth(screen.frame) + 1, height: NSHeight(screen.frame) + 1)
        if NSPointInRect(p, screenBounds) { return screen }
    }
    return nil
}

private func is_desktop_window(_ window: AXUIElement) -> Bool {
    guard let posValue = axCopy(window, kAXPositionAttribute as CFString) else { return false }
    var cgPos = CGPoint.zero
    let desktopWindow = AXValueGetValue(posValue as! AXValue, .cgPoint, &cgPos) &&
        NSEqualPoints(cgPos, desktopOrigin)
    if verbose && desktopWindow { NSLog("Desktop window") }
    return desktopWindow
}

private func is_full_screen(_ window: AXUIElement) -> Bool {
    var fullScreen = false
    guard let posValue = axCopy(window, kAXPositionAttribute as CFString) else { return false }
    var cgPos = CGPoint.zero
    if AXValueGetValue(posValue as! AXValue, .cgPoint, &cgPos), let screen = findScreen(cgPos) {
        if let sizeValue = axCopy(window, kAXSizeAttribute as CFString) {
            var cgSize = CGSize.zero
            if AXValueGetValue(sizeValue as! AXValue, .cgSize, &cgSize), let mainScreen = NSScreen.screens.first {
                let menuBarHeight = max(0, NSMaxY(screen.frame) - NSMaxY(screen.visibleFrame) - 1)
                let screenOriginY = NSMaxY(mainScreen.frame) - NSMaxY(screen.frame)
                fullScreen = cgPos.x == NSMinX(screen.frame) &&
                    cgPos.y == screenOriginY + menuBarHeight &&
                    cgSize.width == NSWidth(screen.frame) &&
                    cgSize.height == NSHeight(screen.frame) - menuBarHeight
            }
        }
    }
    if verbose && fullScreen { NSLog("Full screen window") }
    return fullScreen
}

private func is_main_window(_ app: AXUIElement, _ window: AXUIElement, _ chromeApp: Bool) -> Bool {
    var mainWindow = false
    if let resultValue = axCopy(window, kAXMainAttribute as CFString), let isMain = resultValue as? Bool {
        mainWindow = isMain
        if mainWindow, let subValue = axCopy(window, kAXSubroleAttribute as CFString), let sub = subValue as? String {
            mainWindow = (sub != (kAXDialogSubrole as String))
            if verbose && !mainWindow { NSLog("Dialog window") }
        }
    }

    let finderApp = titleEquals(app, [Finder])
    mainWindow = mainWindow && (chromeApp || finderApp ||
        !titleEquals(window, [NoTitle]) ||
        titleEquals(app, mainWindowAppsWithoutTitle))

    mainWindow = mainWindow || (!finderApp && is_full_screen(window))

    if verbose && !mainWindow { NSLog("Not a main window") }
    return mainWindow
}

private func is_pwa(_ bundleIdentifier: String?) -> Bool {
    guard let bundleIdentifier else { return false }
    let components = bundleIdentifier.components(separatedBy: ".")
    let pake = components.count == 3 && components[1] == Pake
    let pwa = pake || (components.count > 4 && pwas.contains(components[2]) && components[3] == "app")
    if verbose && pwa { NSLog("PWA: %@", components[2]) }
    return pwa
}

private func splitAndTrimCSV(_ value: String) -> [String] {
    if value.isEmpty { return [] }
    return value.components(separatedBy: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}

private func axProcessTrusted(_ prompt: Bool) -> Bool {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
}

// MARK: - where it all happens

private func spaceChanged() {
    spaceHasChanged = true
    oldPoint.x = 0; oldPoint.y = 0
    oldCorrectedPoint = oldPoint
}

private func appActivated() -> Bool {
    if verbose { NSLog("App activated") }
    if !altTaskSwitcher {
        if !activated_by_task_switcher { return false }
        activated_by_task_switcher = false
    }
    appWasActivated = true

    guard let frontmostApp = NSWorkspace.shared.frontmostApplication else { return true }
    let frontmostPid = frontmostApp.processIdentifier

    let frontmostAX = AXUIElementCreateApplication(frontmostPid)
    var activatedWindow = axCopyElement(frontmostAX, kAXMainWindowAttribute as CFString)
    if activatedWindow == nil {
        if verbose { NSLog("No main window, trying focused window") }
        activatedWindow = axCopyElement(frontmostAX, kAXFocusedWindowAttribute as CFString)
    }

    if verbose { NSLog("BundleIdentifier: %@", frontmostApp.bundleIdentifier ?? "(null)") }
    let finderApp = frontmostApp.bundleIdentifier == FinderBundleId
    if finderApp {
        if let window = activatedWindow {
            if is_desktop_window(window) {
                activatedWindow = _previousFinderWindow
            } else {
                _previousFinderWindow = window
            }
        } else {
            activatedWindow = _previousFinderWindow
        }
    }

    if altTaskSwitcher {
        let event = CGEvent(source: nil)
        let mousePoint = event.map { $0.location } ?? .zero

        var ignoreActivated = false
        // TODO: is the uncorrected mousePoint good enough?
        if let mouseWindow = get_mousewindow(mousePoint) {
            if !activated_by_task_switcher {
                var mouseWindowPid: pid_t = 0
                // Checking for mouse movement reduces the problem of the mouse being warped when
                // changing spaces and simultaneously moving the mouse to another screen.
                ignoreActivated = abs(mousePoint.x - oldPoint.x) > 0
                ignoreActivated = ignoreActivated || abs(mousePoint.y - oldPoint.y) > 0
                // Check if the mouse is already hovering above the frontmost app.
                ignoreActivated = ignoreActivated || (AXUIElementGetPid(mouseWindow, &mouseWindowPid) == .success && mouseWindowPid == frontmostPid)
            }
        } else { // dock or top menu
            ignoreActivated = true
        }

        activated_by_task_switcher = false

        if ignoreActivated {
            if verbose { NSLog("Ignoring app activated") }
            return false
        }
    }

    if let window = activatedWindow {
        if verbose { NSLog("Warp mouse") }
        CGWarpMouseCursorPosition(get_mousepoint(window))
    }

    return true
}

private func axObserverCallback(_ observer: AXObserver, _ element: AXUIElement, _ notification: CFString, _ refcon: UnsafeMutableRawPointer?) {
    if CFEqual(notification, kAXUIElementDestroyedNotification as CFString) {
        lastDestroyedMouseWindow_id = UInt64(UInt(bitPattern: refcon))
    }
}

private func onTick() {
    // determine if mouseMoved
    guard let event = CGEvent(source: nil) else {
        if verbose { NSLog("Unable to create CGEvent") }
        return
    }
    var mousePoint = event.location

    let previousPoint = oldPoint
    let mouseXDiff = mousePoint.x - previousPoint.x
    let mouseYDiff = mousePoint.y - previousPoint.y
    oldPoint = mousePoint

    var mouseMoved = abs(mouseXDiff) > CGFloat(mouseDelta)
    mouseMoved = mouseMoved || abs(mouseYDiff) > CGFloat(mouseDelta)
    let mouseStopped = !mouseMoved
    mouseMoved = mouseMoved || propagateMouseMoved
    propagateMouseMoved = false

#if FOCUS_FIRST
    // !delayCount && !raiseDelayCount -> warp only (no focus, no raise)
    if altTaskSwitcher && delayCount == 0 && raiseDelayCount == 0 { return }
    let focusFirst = delayCount != 0 && raiseDelayCount != 1
#else
    // !delayCount -> warp only (no raise)
    if altTaskSwitcher && delayCount == 0 { return }
#endif

    // delayTicks = 0 -> delay disabled, 1 -> delay finished, n -> delay started
    if delayTicks > 1 { delayTicks -= 1 }

    if #available(macOS 12.0, *) {
        // the correction should be applied before we return under certain conditions in the code
        // after it. This ensures oldCorrectedPoint always has a recent value.
        if mouseMoved {
            let screen = findScreen(mousePoint)
            mousePoint.x += mouseXDiff > 0 ? WINDOW_CORRECTION : -WINDOW_CORRECTION
            mousePoint.y += mouseYDiff > 0 ? WINDOW_CORRECTION : -WINDOW_CORRECTION

            if let screen, let mainScreen = NSScreen.screens.first {
                let screenOriginX = NSMinX(screen.frame) - NSMinX(mainScreen.frame)
                let screenOriginY = NSMaxY(mainScreen.frame) - NSMaxY(screen.frame)

                if previousPoint.x > screenOriginX + NSWidth(screen.frame) - WINDOW_CORRECTION {
                    if verbose { NSLog("Screen edge correction") }
                    mousePoint.x = screenOriginX + NSWidth(screen.frame) - SCREEN_EDGE_CORRECTION
                } else if previousPoint.x < screenOriginX + WINDOW_CORRECTION - 1 {
                    if verbose { NSLog("Screen edge correction") }
                    mousePoint.x = screenOriginX + SCREEN_EDGE_CORRECTION
                }

                if previousPoint.y > screenOriginY + NSHeight(screen.frame) - WINDOW_CORRECTION {
                    if verbose { NSLog("Screen edge correction") }
                    mousePoint.y = screenOriginY + NSHeight(screen.frame) - SCREEN_EDGE_CORRECTION
                } else {
                    let menuBarHeight = max(0, NSMaxY(screen.frame) - NSMaxY(screen.visibleFrame) - 1)
                    if mousePoint.y < screenOriginY + menuBarHeight + MENUBAR_CORRECTION {
                        if verbose { NSLog("Menu bar correction") }
                        mousePoint.y = screenOriginY
                    }
                }
            }
            oldCorrectedPoint = mousePoint
        } else {
            mousePoint = oldCorrectedPoint
        }
    }

    if ignoreTimes != 0 {
        ignoreTimes -= 1
        return
    } else if appWasActivated {
        appWasActivated = false
        return
    } else if spaceHasChanged {
        // spaceHasChanged has priority over waiting for the delay
        if mouseMoved { return }
        else if !ignoreSpaceChanged {
            raiseTimes = 3
            delayTicks = 0
        }
        spaceHasChanged = false
    } else if requireMouseStop && !mouseStopped && mouseMoved {
        delayTicks = 0
        // propagate the mouseMoved event to restart the delay if needed
        propagateMouseMoved = true
        return
    }

    // mouseMoved: decide if the window needs raising
    // delayTicks: count down as long as the mouse doesn't move
    // raiseTimes: the window needs raising a couple of times.
    guard mouseMoved || delayTicks != 0 || raiseTimes != 0 else { return }

    // don't raise for as long as something is being dragged (resizing a window for instance)
    var abort = CGEventSource.buttonState(.combinedSessionState, button: .left) ||
        CGEventSource.buttonState(.combinedSessionState, button: .right) ||
        dock_active() || mc_active()

    if !abort && !disableKey.isEmpty {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        var keyAbort = flags.intersection(disableKey) == disableKey
        keyAbort = (keyAbort != invertDisableKey)
        abort = keyAbort
    }

    let frontmostApp = NSWorkspace.shared.frontmostApplication
    if let bundleId = frontmostApp?.bundleIdentifier, (stayFocusedBundleIds ?? []).contains(bundleId) {
        abort = true
    }

    if abort {
        if verbose { NSLog("Abort focus/raise") }
        raiseTimes = 0
        delayTicks = 0
        return
    }

    guard let mouseWindow = get_mousewindow(mousePoint) else { return }
    var mouseWindowPid: pid_t = 0
    guard AXUIElementGetPid(mouseWindow, &mouseWindowPid) == .success else { return }

    var mouseWindowId: CGWindowID = 0
    _ = _AXUIElementGetWindow(mouseWindow, &mouseWindowId)
    let mouseWindowPresent = UInt64(mouseWindowId) != lastDestroyedMouseWindow_id
    if mouseWindowPresent {
        if mouseWindowId != onTick_previous_id {
            onTick_previous_id = mouseWindowId
            lastDestroyedMouseWindow_id = 0
            raiseTimes = 0
            delayTicks = 0

            axObserver = nil   // ARC releases the previous observer (invalidating its source)

            var newObserver: AXObserver?
            AXObserverCreate(mouseWindowPid, axObserverCallback, &newObserver)
            if let newObserver {
                AXObserverAddNotification(
                    newObserver, mouseWindow, kAXUIElementDestroyedNotification as CFString,
                    UnsafeMutableRawPointer(bitPattern: UInt(mouseWindowId)))
                CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(newObserver), .commonModes)
                axObserver = newObserver
            }
        }
    } else if verbose { NSLog("Mouse window not present") }

#if FOCUS_FIRST
    var workaroundForAppsRaisingOnFocus = false
#endif
    var needsRaise = !invertIgnoreApps && mouseWindowPresent
    let mouseWindowApp = AXUIElementCreateApplication(mouseWindowPid)
    if needsRaise && titleEquals(mouseWindow, [NoTitle, Untitled]) {
        let bundleId = NSRunningApplication(processIdentifier: mouseWindowPid)?.bundleIdentifier
        needsRaise = is_main_window(mouseWindowApp, mouseWindow, is_pwa(bundleId))
        if verbose && !needsRaise { NSLog("Excluding window") }
    } else if needsRaise && titleEquals(mouseWindow, [BartenderBar, Zim, AppStoreSearchResults], ignoreTitles) {
        needsRaise = false
        if verbose { NSLog("Excluding window") }
    } else if mouseWindowPresent {
        if titleEquals(mouseWindowApp, ignoreApps ?? []) {
            needsRaise = invertIgnoreApps
            if verbose { NSLog(invertIgnoreApps ? "Including app" : "Excluding app") }
        }
#if FOCUS_FIRST
        workaroundForAppsRaisingOnFocus = titleEquals(mouseWindowApp, AppsRaisingOnFocus)
#endif
    }

    var focusedWindowId: CGWindowID = 0
#if FOCUS_FIRST
    var mouseWindowPsn = ProcessSerialNumber()
    var focusedWindowPsn = ProcessSerialNumber()
    var hasFocusedPsn = false
#endif
    if needsRaise {
        let frontmostPid = frontmostApp?.processIdentifier ?? -1
        let frontmostAX = AXUIElementCreateApplication(frontmostPid)
        if let focusedWindow = axCopyElement(frontmostAX, kAXFocusedWindowAttribute as CFString) {
            if verbose { logWindowTitle("Focused window", focusedWindow) }
            _ = _AXUIElementGetWindow(focusedWindow, &focusedWindowId)
            needsRaise = mouseWindowId != focusedWindowId
#if FOCUS_FIRST
            if !focusFirst {
                needsRaise = needsRaise && !contained_within(focusedWindow, mouseWindow)
            } else {
                needsRaise = needsRaise && is_main_window(frontmostAX, focusedWindow, is_pwa(frontmostApp?.bundleIdentifier)) &&
                    ((mouseWindowPid != frontmostPid && !workaroundForAppsRaisingOnFocus) || !contained_within(focusedWindow, mouseWindow))
                if needsRaise {
                    if ar_GetProcessForPID(frontmostPid, &focusedWindowPsn) == noErr { hasFocusedPsn = true }
                }
            }
#else
            needsRaise = needsRaise && !contained_within(focusedWindow, mouseWindow)
#endif
        } else {
            if verbose { NSLog("No focused window") }
            if axCopyElement(frontmostAX, kAXMainWindowAttribute as CFString) != nil {
                needsRaise = false
            }
        }
    }

    if needsRaise {
        if delayTicks == 0 {
            // start the delay
            delayTicks = delayCount
        }
        if raiseTimes != 0 || delayTicks == 1 {
            delayTicks = 0   // disable delay

            if raiseTimes != 0 { raiseTimes -= 1 } else { raiseTimes = 3 }
#if FOCUS_FIRST
            if focusFirst {
                if ar_GetProcessForPID(mouseWindowPid, &mouseWindowPsn) == noErr {
                    var floatingWindow = false
                    if let subValue = axCopy(mouseWindow, kAXSubroleAttribute as CFString), let sub = subValue as? String {
                        floatingWindow = sub == (kAXFloatingWindowSubrole as String) ||
                            sub == (kAXSystemFloatingWindowSubrole as String) ||
                            sub == (kAXUnknownSubrole as String)
                    }
                    if !floatingWindow {
                        if !workaroundForAppsRaisingOnFocus || raiseDelayCount == 0 {
                            // TODO: method below seems unable to focus floating windows
                            if hasFocusedPsn {
                                withUnsafeMutablePointer(to: &focusedWindowPsn) { focusedPtr in
                                    window_manager_focus_window_without_raise(&mouseWindowPsn, mouseWindowId, focusedPtr, focusedWindowId)
                                }
                            } else {
                                window_manager_focus_window_without_raise(&mouseWindowPsn, mouseWindowId, nil, focusedWindowId)
                            }
                        }
                    } else if verbose { NSLog("Unable to focus floating window") }
                    _lastFocusedWindow = mouseWindow   // ARC retains
                    lastFocusedWindow_pid = mouseWindowPid
                    if raiseDelayCount != 0 { workspaceWatcher?.windowFocused(mouseWindow) }
                }
            } else {
                raiseAndActivate(mouseWindow, mouseWindowPid)
            }
#else
            raiseAndActivate(mouseWindow, mouseWindowPid)
#endif
        }
    } else {
        raiseTimes = 0
        delayTicks = 0
    }
}

private func eventTapCallback(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent, _ userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    let flags = event.flags
    let commandPressed = flags.intersection(TASK_SWITCHER_MODIFIER_KEY) == TASK_SWITCHER_MODIFIER_KEY

    if !commandPressed && commandTabPressed {
        commandTabPressed = false
        activated_by_task_switcher = true
        ignoreTimes = 3
    }

    if !commandPressed && commandGravePressed {
        commandGravePressed = false
        activated_by_task_switcher = true
        ignoreTimes = 3
        workspaceWatcher?.onAppActivated()
    }

    if type == .keyDown {
        let keycode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        if keycode == CGKeyCode(kVK_Tab) {
            commandTabPressed = commandTabPressed || commandPressed
        } else if warpMouse && keycode == CGKeyCode(kVK_ANSI_Grave) {
            commandGravePressed = commandGravePressed || commandPressed
        }
    } else if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if verbose { NSLog("Got event tap disabled event, re-enabling...") }
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
    }

    return Unmanaged.passUnretained(event)
}

// MARK: - notifications

private final class MDWorkspaceWatcher: NSObject {
    override init() {
        super.init()
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(spaceChangedNotification(_:)),
                           name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        if warpMouse {
            center.addObserver(self, selector: #selector(appActivatedNotification(_:)),
                               name: NSWorkspace.didActivateApplicationNotification, object: nil)
            if verbose { NSLog("Registered app activated selector") }
        }
    }

    deinit { NSWorkspace.shared.notificationCenter.removeObserver(self) }

    @objc private func spaceChangedNotification(_ notification: Notification) {
        if verbose { NSLog("Space changed") }
        spaceChanged()
    }

    @objc private func appActivatedNotification(_ notification: Notification) {
        if verbose { NSLog("App activated, waiting %0.3fs", Double(ACTIVATE_DELAY_MS) / 1000.0) }
        perform(#selector(onAppActivated), with: nil, afterDelay: Double(ACTIVATE_DELAY_MS) / 1000.0)
    }

    @objc func onAppActivated() {
        if appActivated() && cursorScale != oldScale {
            if verbose { NSLog("Set cursor scale after %0.3fs", Double(SCALE_DELAY_MS) / 1000.0) }
            perform(#selector(onSetCursorScale(_:)), with: NSNumber(value: cursorScale), afterDelay: Double(SCALE_DELAY_MS) / 1000.0)
            perform(#selector(onSetCursorScale(_:)), with: NSNumber(value: oldScale), afterDelay: Double(SCALE_DURATION_MS) / 1000.0)
        }
    }

    @objc private func onSetCursorScale(_ scale: NSNumber) {
        if verbose { NSLog("Set cursor scale: %@", scale) }
        _ = CGSSetCursorScale(CGSMainConnectionID(), scale.floatValue)
    }

    @objc func onTickTimer(_ timerInterval: NSNumber) {
        if !engineActive { return }
        perform(#selector(onTickTimer(_:)), with: timerInterval, afterDelay: TimeInterval(timerInterval.floatValue))
        onTick()
    }

#if FOCUS_FIRST
    func windowFocused(_ window: AXUIElement) {
        if verbose { NSLog("Window focused, waiting %0.3fs", Double(raiseDelayCount * pollMillis) / 1000.0) }
        let token = UInt64(UInt(bitPattern: Unmanaged.passUnretained(window).toOpaque()))
        perform(#selector(onWindowFocused(_:)), with: NSNumber(value: token), afterDelay: Double(raiseDelayCount * pollMillis) / 1000.0)
    }

    @objc private func onWindowFocused(_ windowToken: NSNumber) {
        guard let lastFocused = _lastFocusedWindow else { return }
        let lastToken = UInt64(UInt(bitPattern: Unmanaged.passUnretained(lastFocused).toOpaque()))
        if windowToken.uint64Value == lastToken {
            raiseAndActivate(lastFocused, lastFocusedWindow_pid)
        } else if verbose { NSLog("Ignoring window focused event") }
    }
#endif
}

// MARK: - Quiver engine wrapper

/// Configuration for one AutoRaise engine session. Field meanings mirror the AutoRaise CLI parameters.
final class AutoRaiseConfig {
    var pollMillis: Int = 50           // >= 20, default 50
    var delay: Int = 0                 // 0 = no raise, 1 = no delay, n = (n-1)*pollMillis
    var focusDelay: Int = 0            // FOCUS_FIRST only; 0 = disabled
    var warpX: Float = 0.5             // 0..1
    var warpY: Float = 0.5             // 0..1
    var scale: Float = 2               // cursor scale after warp (>= 1)
    var warpEnabled: Bool = false      // warp mouse on cmd-tab / cmd-grave
    var altTaskSwitcher: Bool = false
    var requireMouseStop: Bool = false
    var ignoreSpaceChanged: Bool = false
    var invertDisableKey: Bool = false
    var invertIgnoreApps: Bool = false
    var ignoreApps: String?            // comma-separated
    var ignoreTitles: String?          // comma-separated regexes
    var stayFocusedBundleIds: String?  // comma-separated
    var disableKey: String?            // "control" | "option" | "disabled"
    var mouseDelta: Float = 0          // 0 = most sensitive
    var verbose: Bool = false
    init() {}
}

/// Controllable wrapper around the AutoRaise focus-follows-mouse engine. The engine uses
/// process-global state, so only one may run at a time (Quiver creates exactly one). `start`/`stop`
/// install and fully tear down the CGEventTap, AX observers, workspace notifications, and poll timer
/// on the current (main) run loop, so it can be toggled repeatedly without leaking or crashing.
final class AutoRaiseEngine {

    /// True if the engine was compiled with experimental FOCUS_FIRST (focus-before-raise) support.
    static var focusFirstAvailable: Bool {
#if FOCUS_FIRST
        return true
#else
        return false
#endif
    }

    static func isAccessibilityTrusted() -> Bool { axProcessTrusted(false) }
    static func promptAccessibility() -> Bool { axProcessTrusted(true) }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    var isRunning: Bool { engineActive }

    func start(config: AutoRaiseConfig) {
        if engineActive { return }

        // Map configuration onto the engine globals (mirrors AutoRaise main()).
        delayCount = config.delay
        warpX = config.warpX
        warpY = config.warpY
        cursorScale = config.scale < 1 ? 2.0 : config.scale
        verbose = config.verbose
        altTaskSwitcher = config.altTaskSwitcher
        mouseDelta = config.mouseDelta < 0 ? 0 : config.mouseDelta
        pollMillis = config.pollMillis < 20 ? 50 : config.pollMillis
        requireMouseStop = config.requireMouseStop
        ignoreSpaceChanged = config.ignoreSpaceChanged
        invertIgnoreApps = config.invertIgnoreApps
        invertDisableKey = config.invertDisableKey

        warpMouse = config.warpEnabled && warpX >= 0 && warpX <= 1 && warpY >= 0 && warpY <= 1

#if FOCUS_FIRST
        if config.focusDelay > 0 {
            raiseDelayCount = delayCount
            delayCount = config.focusDelay
        } else {
            raiseDelayCount = 1
        }
        if delayCount == 0 && raiseDelayCount == 0 { delayCount = 1 }
#else
        if delayCount == 0 { delayCount = 1 }
#endif

        var ignoreAppsList = (config.ignoreApps?.isEmpty == false) ? splitAndTrimCSV(config.ignoreApps!) : []
        ignoreAppsList.append(AssistiveControl)
        ignoreApps = ignoreAppsList

        ignoreTitles = (config.ignoreTitles?.isEmpty == false) ? splitAndTrimCSV(config.ignoreTitles!) : []
        stayFocusedBundleIds = (config.stayFocusedBundleIds?.isEmpty == false) ? splitAndTrimCSV(config.stayFocusedBundleIds!) : []

        if config.disableKey == "control" {
            disableKey = .maskControl
        } else if config.disableKey == "option" {
            disableKey = .maskAlternate
        } else {
            disableKey = []
        }

        // Reset transient state so a restart is clean.
        spaceHasChanged = false
        appWasActivated = false
        activated_by_task_switcher = false
        propagateMouseMoved = false
        ignoreTimes = 0
        raiseTimes = 0
        delayTicks = 0
        oldPoint = .zero
        oldCorrectedPoint = .zero
        lastDestroyedMouseWindow_id = 0

        // Don't prompt on start; the Quiver UI's "Grant Access" button calls promptAccessibility
        // explicitly. (AX calls simply no-op until access is granted.)
        _ = CGSGetCursorScale(CGSMainConnectionID(), &oldScale)

        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: mask, callback: eventTapCallback, userInfo: nil)
        if let eventTap {
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
            if let source {
                eventTapRunLoopSource = source
                CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
        }

        workspaceWatcher = MDWorkspaceWatcher()
        engineActive = true

#if FOCUS_FIRST
        if altTaskSwitcher || raiseDelayCount != 0 || delayCount != 0 {
            workspaceWatcher?.onTickTimer(NSNumber(value: Float(pollMillis) / 1000.0))
        }
#else
        if altTaskSwitcher || delayCount != 0 {
            workspaceWatcher?.onTickTimer(NSNumber(value: Float(pollMillis) / 1000.0))
        }
#endif

        findDockApplication()
        findDesktopOrigin()
    }

    func stop() {
        if !engineActive { return }
        engineActive = false

        if let workspaceWatcher {
            NSObject.cancelPreviousPerformRequests(withTarget: workspaceWatcher)
        }
        workspaceWatcher = nil

        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            if let eventTapRunLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), eventTapRunLoopSource, .commonModes)
            }
            eventTapRunLoopSource = nil
            CFMachPortInvalidate(eventTap)
        }
        eventTap = nil

        if let axObserver {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(axObserver), .commonModes)
        }
        axObserver = nil

        _previousFinderWindow = nil
        _dock_app = nil
#if FOCUS_FIRST
        _lastFocusedWindow = nil
#endif

        ignoreApps = nil
        ignoreTitles = nil
        stayFocusedBundleIds = nil

        spaceHasChanged = false
        appWasActivated = false
        activated_by_task_switcher = false
        propagateMouseMoved = false
        ignoreTimes = 0
        raiseTimes = 0
        delayTicks = 0
        delayCount = 0
        oldPoint = .zero
        oldCorrectedPoint = .zero
        desktopOrigin = .zero
        lastDestroyedMouseWindow_id = 0
    }
}
