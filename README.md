# Quiver

A single macOS menu-bar app that holds a quiver of small utilities you can flip on and off
individually. It lives in the menu bar, runs quietly in the background, and can launch at login.

Quiver merges two previously separate apps — **AutoRaise** (focus-follows-mouse) and
**HostsMachine** (an `/etc/hosts` editor) — into one pluggable hub, and adds **Keep Awake**.

## Utilities

| Utility | What it does | Permission |
| --- | --- | --- |
| **AutoRaise** | Raises and focuses the window under your pointer (focus-follows-mouse), with a configurable delay, hold-to-pause key, app exclusions, optional focus-first, and pointer-warp on app switch. | Accessibility |
| **Hosts** | View, edit, enable/disable, add, and remove entries in `/etc/hosts`. Optionally install a one-time helper so edits stop asking for your password. | Admin (on write) |
| **Keep Awake** | Prevents your Mac from sleeping while on, with an optional auto-off timer and a "keep the display awake too" option. | None |

## Features

- **Menu-bar hub** — one icon; click for a popover listing every utility with on/off switches and inline quick-controls. Right-click for a simple menu.
- **Full window** — a sidebar + detail layout for each utility's complete settings, plus a General pane.
- **Runs in the background** — no Dock icon by default (a Dock icon appears only while a window is open). Closing a window hides Quiver to the menu bar; only **Quit Quiver** fully exits.
- **Launch at login** — optionally start hidden in the menu bar.
- **Remembers everything** — which utilities are on and each utility's settings persist across restarts; enabled utilities auto-start on launch.
- **Single instance**, About panel, verbose-logging toggle, and clear permission prompts with deep links to System Settings.

## Build & install

Requires macOS 13+ and the Xcode command-line tools.

```bash
./install.sh        # build, install to ~/Applications/Quiver.app, add a Desktop alias, launch
```

Or step by step:

```bash
./build.sh          # build build/Quiver.app (set ARCHS="arm64 x86_64" for a universal build)
make run            # build and launch from ./build
make dmg            # package build/Quiver.dmg
make clean
```

On first launch, open the menu-bar popover and turn on the utilities you want:

- **AutoRaise** → click **Grant Access** and enable Quiver under System Settings → Privacy & Security → Accessibility.
- **Hosts** → edits use the macOS admin prompt; optionally turn on **Passwordless writes** to approve once.

## Adding a new utility

Quiver is built around a small `UtilityModule` base class
([Sources/Quiver/UtilityModule.swift](Sources/Quiver/UtilityModule.swift)). To add a utility:

1. Subclass `UtilityModule`; override `start()`/`stop()` (for an on/off engine) or set
   `isToggleable: false` (for a "tool" you just open).
2. Override `statusSummary`, `permission`, `makeQuickControls()`, and `makeSettingsView()` as needed.
3. Register it in `AppController.makeModules()`
   ([Sources/Quiver/AppController.swift](Sources/Quiver/AppController.swift)).

The shell handles persistence, the menu bar, windows, launch-at-login, and error alerts for you.

## Layout

```
Sources/Quiver/            Swift app shell (AppController, ModuleManager, UI, AppSettings, LoginItem)
Sources/Quiver/Modules/    KeepAwake, Hosts, AutoRaise modules
Sources/AutoRaiseEngine/   Objective-C++ AutoRaise engine + bridging header
Sources/QuiverHelper/      Root-owned helper for passwordless /etc/hosts writes
App/                       Info.plist, entitlements
scripts/                   Icon generator, DMG packager
```

## License & credits

Quiver bundles the **AutoRaise** engine by sbmpost, which is licensed under the **GPLv3**. As a
combined work, Quiver is distributed under the **GPLv3** — see [LICENSE.md](LICENSE.md) and
[CREDITS.md](CREDITS.md). This is for personal use; if you distribute Quiver, you must comply with
the GPLv3.
