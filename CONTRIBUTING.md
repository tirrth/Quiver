# Contributing to Quiver

Thanks for your interest in Quiver! It's a free, open-source macOS menu-bar app, and contributions —
bug reports, fixes, new utilities, docs — are all welcome.

## License

Quiver is distributed under the **GPLv3** (it builds on the GPLv3 AutoRaise engine). By contributing,
you agree your contributions are licensed under the GPLv3 too, and please don't add code that isn't
GPLv3-compatible.

## Getting set up

You'll need **macOS 13+** and the **Xcode command-line tools** (`xcode-select --install`).

```bash
git clone https://github.com/tirrth/Quiver.git
cd Quiver
./build.sh        # builds build/Quiver.app
make run          # build and launch
```

Other handy targets: `make` (build), `make dmg` (package), `make clean`. There's no `.xcodeproj` —
the build is a plain `swiftc` invocation in `build.sh`, so any new `.swift` file under `Sources/` is
picked up automatically.

## Project layout

| Path | What's there |
| --- | --- |
| `Sources/Quiver/` | The app shell — menu bar, windows, settings, persistence, launch-at-login |
| `Sources/Quiver/Modules/` | One self-contained folder per utility |
| `Sources/AutoRaiseEngine/` | The Objective-C++ window-raise engine (GPLv3) + bridging header |
| `Sources/QuiverHelper/` | A small root-owned helper for passwordless `/etc/hosts` writes |
| `App/` | `Info.plist`, entitlements |

Each utility is a `UtilityModule` (see `Sources/Quiver/UtilityModule.swift`). The shell handles
persistence, the menu bar, windows, and error alerts — a module just describes itself and its behavior.

## Adding a utility

1. Add a folder under `Sources/Quiver/Modules/` with your module.
2. Subclass `UtilityModule`. Override `start()`/`stop()` for an on/off engine, or set
   `isToggleable: false` for a "tool" you just open.
3. Implement `statusSummary`, `permission`, `makeQuickControls()`, and `makeSettingsView()` as needed.
4. Register it in `AppController.makeModules()`.
5. Persist any settings under a `module.<your-id>.*` key namespace (see the existing modules).

## Submitting changes

1. **Fork** the repo and create a branch (`git checkout -b my-change`).
2. Keep PRs **focused** — one feature or fix per PR is easiest to review.
3. **Match the surrounding code** — naming, formatting, and comment style. No new dependencies without
   a good reason; Quiver is intentionally pure Swift/AppKit (no Electron, no third-party SDKs).
4. **Build and run locally** (`./build.sh` and launch the app) before opening the PR.
5. Open the PR with a short description of *what* changed and *why*. Screenshots help for UI changes.

## Bugs & ideas

Open an [issue](https://github.com/tirrth/Quiver/issues) for bugs or feature requests. For bugs,
include your macOS version and clear steps to reproduce.

## Be kind

Be respectful and constructive in issues and reviews — we're all here to make a nice little app.
