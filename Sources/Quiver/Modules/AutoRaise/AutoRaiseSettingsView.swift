import SwiftUI

/// Compact controls shown inline in the menu-bar popover when AutoRaise is on.
struct AutoRaiseQuickControls: View {
    @ObservedObject var module: AutoRaiseModule

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "timer").foregroundStyle(.secondary).font(.caption)
            Picker("", selection: Binding(
                get: { module.delayMillis },
                set: { module.setDelayMillis($0) }
            )) {
                ForEach(AutoRaiseModule.delayChoices, id: \.self) { ms in
                    Text(AutoRaiseModule.delayLabel(ms)).tag(ms)
                }
            }
            .labelsHidden().controlSize(.small).frame(maxWidth: 110)

            Spacer()

            if module.focusFirstAvailable {
                Toggle("Focus first", isOn: Binding(
                    get: { module.focusFirst },
                    set: { module.setFocusFirst($0) }
                ))
                .toggleStyle(.checkbox).controlSize(.small).font(.caption)
            }
        }
    }
}

/// Full settings pane shown in the main window.
struct AutoRaiseSettingsView: View {
    @ObservedObject var module: AutoRaiseModule
    @State private var ignoreAppsText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Card(title: "Behavior") {
                SettingRow(
                    title: "Raise delay",
                    subtitle: "How long to hover before the window is raised. “Instant” raises as soon as the pointer settles on it."
                ) {
                    Picker("", selection: Binding(
                        get: { module.delayMillis },
                        set: { module.setDelayMillis($0) }
                    )) {
                        ForEach(AutoRaiseModule.delayChoices, id: \.self) { ms in
                            Text(AutoRaiseModule.delayLabel(ms)).tag(ms)
                        }
                    }
                    .labelsHidden().frame(width: 130)
                }

                Divider()

                SettingRow(
                    title: "Require the mouse to stop",
                    subtitle: "Only raise once the pointer stops moving, so passing over a window on the way elsewhere doesn’t raise it."
                ) {
                    Toggle("", isOn: Binding(
                        get: { module.requireMouseStop },
                        set: { module.setRequireMouseStop($0) }
                    )).labelsHidden().toggleStyle(.switch)
                }

                if module.focusFirstAvailable {
                    Divider()
                    SettingRow(
                        title: "Focus first, then raise",
                        subtitle: "Experimental: give the hovered window keyboard focus immediately, and only raise it after the delay. Relies on private APIs."
                    ) {
                        Toggle("", isOn: Binding(
                            get: { module.focusFirst },
                            set: { module.setFocusFirst($0) }
                        )).labelsHidden().toggleStyle(.switch)
                    }
                }

                Divider()

                SettingRow(
                    title: "Hold-to-pause key",
                    subtitle: "Hold this key to temporarily pause AutoRaise (e.g. while reaching across windows)."
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
                    Text("Comma-separated app names that should never be auto-raised (e.g. “IntelliJ IDEA, WebStorm”).")
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
