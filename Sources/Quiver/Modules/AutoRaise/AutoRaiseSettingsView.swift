import SwiftUI

/// Compact controls shown inline in the menu-bar popover when Follow Focus is on.
struct AutoRaiseQuickControls: View {
    @ObservedObject var module: AutoRaiseModule

    private var delayChoices: [Int] {
        module.mode == .focusThenRaise ? AutoRaiseModule.focusRaiseDelayChoices : AutoRaiseModule.raiseDelayChoices
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("", selection: Binding(
                get: { module.mode },
                set: { module.setMode($0) }
            )) {
                ForEach(module.availableModes) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .labelsHidden().controlSize(.small)

            if module.mode != .focusOnly {
                HStack(spacing: 6) {
                    Image(systemName: "timer").foregroundStyle(.secondary).font(.caption)
                    Picker("", selection: Binding(
                        get: { module.raiseDelayMillis },
                        set: { module.setRaiseDelay($0) }
                    )) {
                        ForEach(delayChoices, id: \.self) { ms in
                            Text(AutoRaiseModule.delayLabel(ms)).tag(ms)
                        }
                    }
                    .labelsHidden().controlSize(.small).frame(maxWidth: 110)
                    Spacer()
                }
            }
        }
    }
}

/// Full settings pane shown in the main window.
struct AutoRaiseSettingsView: View {
    @ObservedObject var module: AutoRaiseModule
    @State private var ignoreAppsText: String = ""

    private var delayChoices: [Int] {
        module.mode == .focusThenRaise ? AutoRaiseModule.focusRaiseDelayChoices : AutoRaiseModule.raiseDelayChoices
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Card(title: "Behavior") {
                VStack(alignment: .leading, spacing: 8) {
                    SettingRow(
                        title: "When you hover a window",
                        subtitle: nil
                    ) {
                        Picker("", selection: Binding(
                            get: { module.mode },
                            set: { module.setMode($0) }
                        )) {
                            ForEach(module.availableModes) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .labelsHidden().frame(width: 220)
                    }
                    Text(module.mode.explanation)
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !module.focusFirstAvailable {
                        Text("Focus-only modes aren’t available on this Mac (the focus-first engine support isn’t present).")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }

                if module.mode != .focusOnly {
                    Divider()
                    SettingRow(
                        title: module.mode == .focusThenRaise ? "Raise delay" : "Raise delay",
                        subtitle: module.mode == .focusThenRaise
                            ? "How long to keep hovering before the focused window is brought to the front."
                            : "How long to hover before the window is raised. “Instant” raises as soon as the pointer settles."
                    ) {
                        Picker("", selection: Binding(
                            get: { module.raiseDelayMillis },
                            set: { module.setRaiseDelay($0) }
                        )) {
                            ForEach(delayChoices, id: \.self) { ms in
                                Text(AutoRaiseModule.delayLabel(ms)).tag(ms)
                            }
                        }
                        .labelsHidden().frame(width: 130)
                    }
                }

                Divider()

                SettingRow(
                    title: "Require the mouse to stop",
                    subtitle: "Only act once the pointer stops moving, so passing over a window on the way elsewhere doesn’t trigger it."
                ) {
                    Toggle("", isOn: Binding(
                        get: { module.requireMouseStop },
                        set: { module.setRequireMouseStop($0) }
                    )).labelsHidden().toggleStyle(.switch)
                }

                Divider()

                SettingRow(
                    title: "Hold-to-pause key",
                    subtitle: "Hold this key to temporarily pause Follow Focus (e.g. while reaching across windows)."
                ) {
                    Picker("", selection: Binding(
                        get: { module.disableKey },
                        set: { module.setDisableKey($0) }
                    )) {
                        Text("Control").tag("control")
                        Text("Option").tag("option")
                        Text("Off").tag("disabled")
                    }
                    .labelsHidden().frame(width: 130)
                }

                Divider()

                SettingRow(
                    title: "Warp pointer on app switch",
                    subtitle: "When you cmd-tab or cmd-` to another app, jump the pointer onto its window so hovering keeps working."
                ) {
                    Toggle("", isOn: Binding(
                        get: { module.warpOnSwitch },
                        set: { module.setWarpOnSwitch($0) }
                    )).labelsHidden().toggleStyle(.switch)
                }
            }

            Card(title: "Exclusions") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Ignore these apps")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Comma-separated app names that should never be auto-raised or focused (e.g. “IntelliJ IDEA, WebStorm”).")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    TextField("App One, App Two", text: $ignoreAppsText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { module.setIgnoreApps(ignoreAppsText) }
                    Text("Press Return to apply.").font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .onAppear { ignoreAppsText = module.ignoreApps }
    }
}
