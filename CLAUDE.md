# Quiver — project guide for Claude

Quiver is a **macOS menu-bar utility hub** (Swift / AppKit / SwiftUI). It hosts a set of
`UtilityModule`s — including a **pure-Swift port of AutoRaise** (GPLv3; attribution must remain) plus
tools like Drop Deck (Shelf), Net Speed, Eject Drives, Metal HUD, Reroute It, Glance Me, etc. The
left-click menu-bar icon (a gem) opens a floating, Control Center–style glass panel of resizable tiles.

- **Bundle:** `com.tirth.quiver`, `LSUIElement` (agent app, no Dock icon by default; flips to `.regular`
  while a window is open). Deploy target macOS 13.0, but uses macOS 26 (Tahoe) Liquid Glass APIs behind
  `#available(macOS 26.0, *)`.
- **Build / run:** `./build.sh` then `./install.sh` (installs to `/Applications/Quiver.app`). No Xcode
  project — it's a script build.

## Where things live
- `Sources/Quiver/AppController.swift` — app shell: status item, hub panel, main window, lifecycle,
  activation-policy flipping.
- `Sources/Quiver/UI/ControlCenter/` — the hub: `HubPanel` (floating NSPanel), `HubGridView`, `ModuleTile`,
  `Glass`, `TileGrid`, `TileSize`.
- `Sources/Quiver/Modules/` — the utility modules (each an `UtilityModule`). AutoRaise engine is at
  `Modules/AutoRaise/Engine/` (Swift).
- `Sources/Quiver/UI/` — main window, settings, icon picker, etc.

## Read before changing the hub / glass
**`docs/control-center-hub.md`** captures hard-won, heavily-tested learnings about the Control Center
panel. Highlights so you don't re-test them:
- Glass = `NSGlassEffectView` with **`style = .clear`** (translucent, samples the wallpaper). White
  text via `.environment(\.colorScheme, .dark)` on the content — **don't** pin the panel to `.darkAqua`.
- **Tile-merging ("blob") does NOT work** — `GlassEffectContainer` faints a dense grid at any spacing.
  Proven; don't re-attempt.
- The panel must **never become key / activate the app** (LSUIElement → activating hides the system menu
  bar). It's a nonactivating panel ordered front without activation.
- Fullscreen menu bar is kept pinned by posting HIToolbox `begin/endMenuTrackingNotification`.
- Panel positioning validates the status-item anchor + clamps on-screen + retries (fresh launches jostle
  the status item).

## Verifying UI changes
**`screencapture` works here** — use it (don't guess at visuals). The reliable workflow (temp `SIGUSR1`
trigger → `CGWindowList` rect → `screencapture -R` → read PNG), plus the gotchas (warm up the status item,
wait for the old process to die so you don't capture a stale build, dynamic wallpaper), are in
`docs/control-center-hub.md`.

## Conventions
- **Don't auto-commit/push** — make changes and let the maintainer review/commit.
- **No `Co-Authored-By` trailer** on Quiver commits.
- Keep the **AutoRaise GPLv3 attribution** (see `CREDITS.md` / `LICENSE.md`).
