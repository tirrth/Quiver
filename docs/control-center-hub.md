# Control Center–style Hub — hard-won learnings

This documents the non-obvious decisions behind the menu-bar hub (the floating "Control Center" panel),
so they don't get re-litigated or re-tested. Most of these cost a lot of trial-and-error. **Read this
before touching `UI/ControlCenter/` (`HubPanel`, `HubGridView`, `ModuleTile`, `Glass`, `TileGrid`).**

## Architecture

- The hub is a **floating borderless `NSPanel`** (`UI/ControlCenter/HubPanel.swift`), **not an `NSMenu`**.
  The product decision was the Control Center floating-tiles look over a native menu. The old NSMenu hub
  (`buildHubMenu` in `AppController`) is dormant.
- The status item uses **target/action** (`toggleHubPanel`), not `statusItem.menu`.
- Layout: 295pt-wide content, **65pt tiles, 4 columns**, ~11.67pt gaps. `TileGridLayout` (a custom
  SwiftUI `Layout`) first-fit-packs variable tiles (small 1×1 / wide 2×1 / large 2×2).

## The glass (matching Control Center) — took *many* iterations

Use **`NSGlassEffectView`** (macOS 26 real Liquid Glass), wrapped in an `NSViewRepresentable`, as a
SwiftUI `.background` (`Glass.swift`). Key facts, each verified by live screenshot:

- **Why `NSGlassEffectView`, not `NSVisualEffectView` or SwiftUI `glassEffect`:** it "pulls pixels from
  the desktop and windows behind it" — real Liquid Glass *and* wallpaper frosting. `NSVisualEffectView`
  is the older frosted vibrancy. (SwiftUI `glassEffect` *also* samples the desktop here and looks
  equivalent — it's a fine alternative — but `NSGlassEffectView` is what's shipped.)
- **`style = .clear`, not `.regular`.** `.regular` renders a milky/opaque slab; `.clear` is the
  translucent, wallpaper-showing Control Center look. (`NSGlassEffectViewStyle` is in the SDK header
  `…/MacOSX*.sdk/…/AppKit.framework/Headers/NSGlassEffectView.h`.)
- **Corners** come from `NSGlassEffectView.cornerRadius` (no mask image). For the pre-26 fallback
  (`NSVisualEffectView`, `.behindWindow`), round with **`maskImage`, NOT `layer.cornerRadius` /
  `layer.masksToBounds`** — the latter disables the blur and renders the view fully transparent.
- **White text/icons** (like CC): `.environment(\.colorScheme, .dark)` on the hub content only. Do **not**
  pin the *panel* appearance to `.darkAqua` — that turns the glass dark. Decouple: the glass renders light
  naturally; the dark color scheme only flips the SwiftUI `.primary`/`.secondary` content colors white.
  A small legibility shadow sits under the white glyphs.

## Tile-merging ("blob") — DO NOT re-attempt

The Control Center "tiles meld into a blob" effect was investigated exhaustively and **does not work for
our dense grid**:

- SwiftUI **`GlassEffectContainer`** (the merge API) **thins/faints the glass** for a dense grid — at any
  `spacing` (even 0), with or without `glassEffectID`. Proven with same-wallpaper, back-to-back captures:
  non-container tiles are crisp; container tiles wash out. It's inherent to the container batching many
  glass elements, not a spacing/wallpaper artifact.
- AppKit **`NSGlassEffectContainerView`** uses the same engine (same fainting) and, when embedded in the
  panel's SwiftUI layout, also breaks rendering/sizing. Four different attachment architectures were tried.
- **Conclusion: merging makes it worse. The non-merged glass is the correct look.** The only thing that
  would change this is grouping controls into shared rounded *regions* (like CC actually does) instead of
  individual circles — a layout redesign, not a glass tweak.

## Keeping the menu bar pinned over fullscreen apps

Over a fullscreen app macOS auto-hides the menu bar. To keep it revealed while the panel is open,
`HubPanel.show()` posts `com.apple.HIToolbox.beginMenuTrackingNotification` (and `…endMenuTracking…` on
close) via `DistributedNotificationCenter`. It prevents an already-revealed bar from auto-hiding (it does
not reveal a hidden one — in practice the user hovered the top to click the gem). Must be posted from the
GUI app process (a CLI tool posting it has no effect).

## Why the panel must never become key / activate the app

Quiver is **`LSUIElement`** (agent app, no menu bar of its own). If the panel becomes the **key window**
while the app is in `.accessory` mode, macOS makes the agent app the menu-bar owner and — finding no menu
bar — **hides the whole system bar**. So the panel is a `.nonactivatingPanel` with
`becomesKeyOnlyIfNeeded = true`, `hidesOnDeactivate = false`, shown via `orderFrontRegardless()`. Never
call `NSApp.activate` for the panel. Controls still get clicks (nonactivating panels deliver mouse events
without taking focus).

## Status-item icon highlight

Manual: `statusItem.button.highlight(true)` on open / `false` on close — **deferred** with
`DispatchQueue.main.async`, because the opening click's own mouse-up clears the highlight otherwise.

## Panel positioning & sizing

- Centered under the icon (top-center anchor, grows downward).
- **Positioning bug fixed:** on a *fresh launch* the status item isn't positioned yet, so the anchor reads
  off-screen and the panel could launch off-screen. `topCenterAnchor` now rejects a frame that isn't in a
  menu bar; `positionPanel` clamps the panel fully on-screen; `show()` retries the anchor after 0.2s.
- **Sizing:** `panel.contentViewController = host` (an `NSHostingController`); the panel is measured from
  `host.view.fittingSize`. **Do not** wrap the hosting view in custom `NSView`s — it couples `fittingSize`
  to the frame (position drift) and child-VC hosting renders transparent. (`NSHostingController.sizingOptions
  = .intrinsicContentSize` is the documented knob if sizing ever needs revisiting.)

## Verifying the UI here (IMPORTANT)

- **`screencapture` works** in this environment (an earlier note that it was "blocked" was wrong). Use it
  to see the panel — don't guess at glass tweaks.
- Workflow: add a temporary `SIGUSR1` handler that calls `toggleHubPanel()`, `kill -USR1 <pid>` to open the
  panel, find its rect via `CGWindowListCopyWindowInfo` (owner `Quiver`, `kCGWindowLayer >= 100`),
  `screencapture -x -R<x,y,w,h>`, then read the PNG. **Warm up** the status item (open+close once) and retry
  until the panel lands on-screen (`y < 80`) — fresh launches jostle the status-item position for ~1s.
- `CGWindowListCreateImage` / `CGDisplayCreateImage` are **removed in macOS 15+** (compile error) — use the
  `screencapture` CLI, not those APIs.
- The desktop wallpaper here is **dynamic** — translucent glass looks darker over darker wallpaper, so
  compare merge/no-merge over the *same* wallpaper (back-to-back captures).
- To compare against the **real Control Center**: open it via AX (`com.apple.controlcenter` →
  `AXExtrasMenuBar` → child whose `AXDescription == "Control Center"` → `AXPress`), then screencapture.
- A reliable build+launch must wait for the old process to fully die before `open` (the single-instance
  guard otherwise re-activates a *stale* build).
