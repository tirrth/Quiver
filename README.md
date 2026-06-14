# Quiver

A single macOS menu-bar app that holds a quiver of small utilities you flip on and off
individually. It lives in the menu bar, runs quietly in the background, and can launch at login.

One app, several focused tools — instead of a separate menu-bar app for every little thing.

## Utilities

| Utility | What it does | Permission |
| --- | --- | --- |
| **Follow Focus** | Raises and focuses the window under your pointer (focus-follows-mouse), with a configurable delay, hold-to-pause key, app exclusions, optional focus-first, and pointer-warp on app switch. | Accessibility |
| **Drop Deck** | A floating tray: drop files, text, links, or images onto it, switch windows or Spaces, then drag them back out anywhere. Drop several at once and they collect into one stack. | None |
| **Keep Awake** | Keeps your Mac from sleeping while on, with an optional auto-off timer and a "keep the display awake too" option. | None |
| **Waypoint** | Toggle `/etc/hosts` entries on and off — and add, edit, or remove them — without opening Terminal. Optionally install a one-time helper so edits stop asking for your password. | Admin (on write) |
| **Glance Me** | A quick webcam check before a call. The camera runs only while it's open. | Camera |

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
./install.sh        # build, install to /Applications/Quiver.app, and launch
```

Or step by step:

```bash
./build.sh          # build build/Quiver.app (set ARCHS="arm64 x86_64" for a universal build)
make run            # build and launch from ./build
make dmg            # package build/Quiver.dmg
make clean
```

On first launch, open the menu-bar popover and turn on the utilities you want:

- **Follow Focus** → click **Grant Access** and enable Quiver under System Settings → Privacy & Security → Accessibility.
- **Waypoint** → edits use the macOS admin prompt; optionally turn on **Passwordless writes** to approve once.
- **Glance Me** → allow camera access when prompted.

## Contributing

Contributions are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) for how to build, the project
layout, and how to add your own utility.

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

```text
Sources/Quiver/            Swift app shell (AppController, ModuleManager, UI, AppSettings, LoginItem)
Sources/Quiver/Modules/    one self-contained folder per utility
Sources/AutoRaiseEngine/   Objective-C++ window-raise engine (the GPLv3 AutoRaise engine) + bridging header
Sources/QuiverHelper/      Root-owned helper for passwordless /etc/hosts writes
App/                       Info.plist, entitlements
scripts/                   Icon generator, DMG packager
```

## License & credits

Quiver's window-raise engine — which powers **Follow Focus** — is the **AutoRaise** engine by sbmpost,
licensed under the **GPLv3**. As a combined work, Quiver is distributed under the **GPLv3** — see
[LICENSE.md](LICENSE.md) and [CREDITS.md](CREDITS.md). If you distribute Quiver, you must comply with
the GPLv3.
