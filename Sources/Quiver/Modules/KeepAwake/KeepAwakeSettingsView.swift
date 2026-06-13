import SwiftUI

/// Compact controls shown inline in the menu-bar popover when Keep Awake is on.
struct KeepAwakeQuickControls: View {
    @ObservedObject var module: KeepAwakeModule

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "timer").foregroundStyle(.secondary).font(.caption)
            Picker("", selection: Binding(
                get: { module.durationMinutes },
                set: { module.setDuration($0) }
            )) {
                ForEach(KeepAwakeModule.durationChoices, id: \.self) { minutes in
                    Text(KeepAwakeModule.durationLabel(minutes)).tag(minutes)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(maxWidth: 130)

            Spacer()

            Toggle("Display", isOn: Binding(
                get: { module.keepDisplayAwake },
                set: { module.setKeepDisplayAwake($0) }
            ))
            .toggleStyle(.checkbox)
            .controlSize(.small)
            .font(.caption)
        }
    }
}

/// Full settings pane shown in the main window.
struct KeepAwakeSettingsView: View {
    @ObservedObject var module: KeepAwakeModule

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Card(title: "Behavior") {
                SettingRow(
                    title: "Duration",
                    subtitle: "Automatically turn Keep Awake off after this long. Choose “Indefinitely” to stay on until you switch it off."
                ) {
                    Picker("", selection: Binding(
                        get: { module.durationMinutes },
                        set: { module.setDuration($0) }
                    )) {
                        ForEach(KeepAwakeModule.durationChoices, id: \.self) { minutes in
                            Text(KeepAwakeModule.durationLabel(minutes)).tag(minutes)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }

                Divider()

                SettingRow(
                    title: "Keep the display awake too",
                    subtitle: "Also prevents the screen from dimming or turning off. Leave off to allow the display to sleep while the system stays awake."
                ) {
                    Toggle("", isOn: Binding(
                        get: { module.keepDisplayAwake },
                        set: { module.setKeepDisplayAwake($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
            }

            if module.isEnabled {
                Label(module.statusSummary, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            }
        }
    }
}
