# Credits & attribution

Quiver is a combined work that builds on the following projects.

## AutoRaise

- Author: **sbmpost** — https://github.com/sbmpost/AutoRaise
- License: **GNU General Public License v3** (see [LICENSE.md](LICENSE.md))
- Use in Quiver: the focus-follows-mouse engine in
  [Sources/AutoRaiseEngine/AutoRaiseEngine.mm](Sources/AutoRaiseEngine/AutoRaiseEngine.mm) is taken
  from AutoRaise's `AutoRaise.mm`. The window-detection, event-tap, mouse-warp, and raise/focus hot
  path is preserved as-is; only the application entry point (`main`), the standalone status-item
  controller, and the config-file reader were removed and replaced with a `start(config:)`/`stop()`
  lifecycle so Quiver can toggle it. Some pieces of AutoRaise are themselves based on `metamove` by
  jmgao and `yabai` by koekeishiya.

Because AutoRaise is GPLv3, **Quiver as a whole is distributed under the GPLv3.**

## HostsMachine

- The `/etc/hosts` parsing/writing engine, the privileged helper, and the launch-at-login mechanism
  originate from the author's own HostsMachine app and were ported into Quiver's `Hosts` module
  ([Sources/Quiver/Modules/Hosts/](Sources/Quiver/Modules/Hosts/)) and
  [Sources/QuiverHelper/](Sources/QuiverHelper/).

## Apple frameworks

Quiver uses AppKit, SwiftUI, IOKit (power assertions for Keep Awake), ApplicationServices /
Accessibility, and the private SkyLight framework (via AutoRaise, for the experimental focus-first
path and cursor scaling).
