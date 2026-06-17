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
- **The exact CC material is `_variant = 8` ("controlCenter") — the public styles are only approximations.**
  ⭐ This is the current recipe (`CCGlassView` in `Glass.swift`), and it's the one that finally reads as CC.
  The two public `NSGlassEffectViewStyle`s each miss: `.regular` is **adaptive/frosted** — over a light
  wallpaper it **over-blurs** ("too much blur" / milky vs CC); `.clear` keeps the wallpaper **crisp** but on
  its own is **too bare/edgeless** and nearly vanishes over a light wallpaper. The *real* Control Center uses
  neither — it uses `NSGlassEffectView`'s **private `_variant` 8**, which is a translucent body **with a
  defined specular rim** and wallpaper sampling. Set it via the private selector `set_variant:` (guarded by
  `responds(to:)`; silently degrades to plain `.clear` if Apple renames it). Verified by a back-to-back
  3-way capture over one wallpaper: `.regular` milky, `.clear` flat, **variant 8 = the CC glass chip**. The
  variant enum (from the `electron-liquid-glass` project) also exposes `_subvariant`/`_scrimState`; the full
  table has `regular=0, clear=1, … controlCenter=8, notificationCenter=9, … cartouchePopover=23`.
- **Force non-subdued, or it frosts when the panel isn't key.** ⚠️ `NSGlassEffectView` flattens to a milky
  frost in its **"subdued"** state whenever its window isn't key — and the hub is a nonactivating panel that
  is *never* key, so it would frost on open and only "wake up" to the live render after interaction. The fix
  is to **override the private `_subduedState` getter to always return `0`** (`@objc(_subduedState)` on
  `CCGlassView`). The framework reads the material's subdued state through that getter, so pinning it to 0
  keeps the live, lensed CC render permanently. (Setting `set_subduedState:` once does **not** stick — the
  framework re-reads it; the getter override is what holds.) This was the "frosted-on-open until I click a
  tile" bug. OK to use the SPI: Quiver is ad-hoc-signed and already links private frameworks (SkyLight).
- **`effectIsInteractive = true` (macOS 27+)** drives the live specular *lensing* as content moves under the
  glass — the visible "animation when you pass text/icons through it," and what makes it feel like CC.
- **Do NOT set the glass `appearance` manually.** ⚠️ Hard-won: forcing `view.appearance = .aqua` to "keep it
  light" **over-frosted** it (milky/opaque) — Apple says explicitly *do not set appearance manually*
  (WWDC25 310); the material adapts by sampling the backdrop, and pinning the appearance defeats that.
- **`tintColor` does NOT fix a "too blue" cast cleanly** — the glass *samples the color behind it* by design;
  CC just usually sits over a neutral desktop while our panel sits over a colored app. A neutral tint
  desaturates but also dulls; the rim/fill recipe above is what was kept.
- **Verify glass over a CONTROLLED backdrop, not the live desktop.** A helper window showing a wallpaper
  image at `level = .popUpMenu - 1`, with the hub above it, lets you screenshot the glass over a known tone
  (the live desktop is hidden behind full-screen apps here). Gotcha: the hub panel must out-rank that
  backdrop — see the `isFloatingPanel`/level ordering note below, or the panel hides *behind* the backdrop.
- **Corners** come from `NSGlassEffectView.cornerRadius` (no mask image). For the pre-26 fallback
  (`NSVisualEffectView`, `.behindWindow`), round with **`maskImage`, NOT `layer.cornerRadius` /
  `layer.masksToBounds`** — the latter disables the blur and renders the view fully transparent.
- **White text/icons** (like CC): `.environment(\.colorScheme, .dark)` on the hub content only. Do **not**
  pin the *panel* appearance to `.darkAqua` — that turns the glass dark. Decouple: the glass renders light
  naturally; the dark color scheme only flips the SwiftUI `.primary`/`.secondary` content colors white.
  A small legibility shadow sits under the white glyphs.
- **Legibility over a WHITE/bright backdrop = a constant dim scrim, NOT a content-color flip.** ⭐⭐ Hard-won;
  do not re-litigate. Measured from a real-CC capture over a pure-white backdrop: **CC keeps its content
  WHITE and dims the glass to a mid-gray** (a real CC tile reads **~190** over white; a bare variant-8 tile
  reads **~243**, so white text washes out — that was the bug). CC does **NOT** flip text to dark. (An earlier
  attempt that sampled the backdrop via ScreenCaptureKit and flipped content dark/light was **wrong** and was
  reverted — verified against the real thing.) The fix is a **constant `Color.black.opacity(0.25)` scrim
  overlaid on the glass** (in `GlassBackdrop`), under the white content: it lands the tile at ~190 over white
  (matched to CC), and because it's constant it also works over dark/colored backdrops — no flip, no
  ScreenCaptureKit, no Screen Recording permission. At 25% opacity the glass still samples + lenses colored
  wallpapers through it. (Pixel check: CC tile ~189, ours ~190; CC gaps/margins are near-white ~244, so there
  is **no** strong full-panel "parent" scrim — the gray is the tiles + their soft shadows.)

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

## Keeping the menu bar revealed over fullscreen apps — SOLVED via SkyLight (`MenuBarReveal`)

Over a full-screen app macOS auto-hides the menu bar, and a floating panel can't hold it via menu tracking
(only a real `NSMenu` does — which is why the *pinned `statusItem.menu` items* keep it). The fix is the
private **SkyLight** SPI `SLSSetMenuBarVisibilityOverrideOnDisplay(cid, displayID, true)` — the same call
SketchyBar uses (`src/misc/extern.h`). `MenuBarReveal.reveal()` sets it on every active display when the hub
opens; `restore()` clears it on close (and at launch, to recover from a crash). Verified by screencapture:
the menu bar appears over a full-screen app while the hub is open and hides again on close.

- It's a **per-display visibility override**, NOT the global "Automatically hide the menu bar" preference
  (`SLSSetMenuBarAutohideEnabled` would change that user setting — avoided). So it never touches System
  Settings; it just forces visibility while open.
- **OK to use a private SPI here:** Quiver is **not** App Store distributed (ad-hoc/local signing) and
  **already links `SkyLight.framework`** (AutoRaise). Declared via `@_silgen_name` (the build is plain
  `swiftc`, no bridging header). Guard against renames: a non-zero `CGError` is harmless (just no reveal).
- `beginMenuTrackingNotification` heartbeat and the `.regular`+`NSApp.activate` flip were tried first and
  **failed** (an event, not a state; and an active `.accessory` app has no menu bar — Apple FB13544993 — and
  `.regular`+activate did not reveal the bar over a full-screen Space). Both removed. Don't re-attempt.

## The one thing a floating panel still CANNOT do — the native highlight

The hub is a **nonactivating, never-key** `.borderless` panel (`orderFrontRegardless()`). The native
status-item highlight needs the panel to be the **key** window — and a key window renders `NSGlassEffectView`
**milky/opaque** instead of crisp/translucent (verified by back-to-back screenshots: key = milky, non-key =
crisp). So the native highlight and crisp CC glass are mutually exclusive for the floating panel; crisp glass
was chosen. The only way to get the highlight too is the `statusItem.menu = hubMenu` (NSMenu) path — which
also gets native positioning for free, at the cost of the detached floating look.

## Panel positioning & sizing

- Centered under the icon (top-center anchor, grows downward).
- **"Is the gem in the menu bar?" test:** use `frame.midY >= screen.visibleFrame.maxY` (the button's center
  is above the usable area). ⚠️ The old test `frame.maxY >= screen.frame.maxY - 4` was too tight for the
  taller macOS 26/27 menu bar (the status item sits ~5.5pt below the top) — it failed *every* time, so the
  anchor always fell back and the panel opened centered/on the wrong display instead of under the gem.
- **Resolve the screen from `button.window?.screen`** and **carry it through** to `positionPanel` — never
  re-derive via `NSScreen.main` (that pushed the panel onto the wrong display). The launch-race fallback
  centers on `screenWithMouse()` (where the click happened), not `NSScreen.main`.
- `positionPanel` clamps the panel fully on-screen against the *resolved* screen's `visibleFrame`; `show()`
  retries the anchor after 0.2s for the fresh-launch race (status item not positioned yet).
- **Level/spaces (don't "disappear" over apps):** set `isFloatingPanel = true` **before** `level = .popUpMenu`
  — `isFloatingPanel` resets the level to `.floating`, so setting the level afterward keeps it at `.popUpMenu`
  (above the menu bar). Use `collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle, .moveToActiveSpace]`
  (Ice's IceBar config). ⚠️ `.canJoinAllSpaces` and `.moveToActiveSpace` are mutually exclusive;
  `.canJoinAllSpaces` stranded the panel on the desktop space, so over a full-screen app it "disappeared" —
  `.moveToActiveSpace` brings it onto the current (incl. full-screen) space.
- **Click-outside dismissal must hit-test the panel frame.** A global mouse-down monitor sees clicks posted
  to *other* apps — and because the panel is nonactivating, clicks ON it are reported there too, so an
  unconditional `close()` dismissed the panel on its own controls. Guard with
  `if !panel.frame.contains(NSEvent.mouseLocation) { close() }`. (With the make-key change above, in-panel
  clicks also keep the panel key, and `didResignKey` handles app-switch/outside dismissal.)
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
