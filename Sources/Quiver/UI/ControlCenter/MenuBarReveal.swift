import CoreGraphics

// Private SkyLight (WindowServer) SPI — the same one SketchyBar uses (`src/misc/extern.h`) — to force the
// system menu bar visible on a display. Quiver already links `SkyLight.framework` (for AutoRaise's
// focus-first), so this resolves at link time; declared via `@_silgen_name` because the build is plain
// `swiftc` (no bridging header).
//
// We use it ONLY to keep the menu bar visible while the hub is open — including over a FULL-SCREEN app,
// where it auto-hides and a floating panel can't hold it (that needs a live NSMenu tracking session). This
// is a per-display *override*, NOT the global "Automatically hide the menu bar" preference, so it never
// changes the user's System Settings; we just toggle it off again on close (and clear it at launch, in case
// a crash left it on).
@_silgen_name("SLSMainConnectionID")
private func SLSMainConnectionID() -> Int32

@_silgen_name("SLSSetMenuBarVisibilityOverrideOnDisplay")
private func SLSSetMenuBarVisibilityOverrideOnDisplay(_ cid: Int32, _ display: CGDirectDisplayID, _ override: Bool) -> CGError

/// Reveals / un-reveals the system menu bar while the hub panel is open.
@MainActor
enum MenuBarReveal {
    private static let cid: Int32 = SLSMainConnectionID()

    /// Keep the menu bar shown for the hub's lifetime — on the display the hub is on **only**, so opening the
    /// hub on one screen doesn't force the *other* screen's menu bar visible (it was revealing all displays).
    /// Clears any prior override first, so re-targeting (e.g. the launch-race reposition onto another display)
    /// never leaves a different screen's bar stuck open. `display == nil` falls back to all displays.
    static func reveal(display: CGDirectDisplayID?) {
        setOverride(false, on: activeDisplays())   // drop any previous reveal first
        if let display {
            _ = SLSSetMenuBarVisibilityOverrideOnDisplay(cid, display, true)
        } else {
            setOverride(true, on: activeDisplays())
        }
    }

    /// Drop the override on every display. Idempotent — safe to call on close, on quit, and at launch (to
    /// clear a leftover override from a crash).
    static func restore() { setOverride(false, on: activeDisplays()) }

    private static func activeDisplays() -> [CGDirectDisplayID] {
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(16, &displays, &count) == .success else { return [] }
        return Array(displays.prefix(Int(count)))
    }

    private static func setOverride(_ on: Bool, on displays: [CGDirectDisplayID]) {
        for display in displays { _ = SLSSetMenuBarVisibilityOverrideOnDisplay(cid, display, on) }
    }
}
