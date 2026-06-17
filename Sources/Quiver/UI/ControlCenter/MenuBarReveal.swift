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

/// Reveals / un-reveals the system menu bar (across all active displays) while the hub panel is open.
@MainActor
enum MenuBarReveal {
    private static let cid: Int32 = SLSMainConnectionID()

    /// Keep the menu bar shown for the hub's lifetime, even over a full-screen app.
    static func reveal() { setOverride(true) }

    /// Drop the override so the bar resumes normal auto-hide. Idempotent — safe to call on close, on quit,
    /// and at launch (to clear a leftover override from a crash).
    static func restore() { setOverride(false) }

    private static func setOverride(_ on: Bool) {
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(16, &displays, &count) == .success else { return }
        for i in 0..<Int(count) { _ = SLSSetMenuBarVisibilityOverrideOnDisplay(cid, displays[i], on) }
    }
}
