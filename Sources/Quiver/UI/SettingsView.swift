import SwiftUI
import UniformTypeIdentifiers

/// App-wide settings, reused both as the standalone Settings window and as the main window's
/// "General" pane.
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var manager: ModuleManager

    var body: some View {
        ScrollView {
            GeneralSettingsContent(settings: settings, manager: manager)
                .padding(20)
        }
        .frame(minWidth: 480, minHeight: 420)
    }
}

struct GeneralSettingsContent: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var manager: ModuleManager

    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "Version \(short)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Card(title: "Startup") {
                SettingRow(
                    title: "Launch Quiver at login",
                    subtitle: "Start automatically when you log in to your Mac."
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.launchAtLogin },
                        set: { settings.setLaunchAtLogin($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }

                Divider()

                SettingRow(
                    title: "Start hidden in the menu bar",
                    subtitle: "When launching at login, don't open a window — just sit in the menu bar."
                ) {
                    Toggle("", isOn: Binding(
                        get: { settings.startHiddenAtLogin },
                        set: { settings.setStartHidden($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!settings.launchAtLogin)
                }
            }

            Card(title: "Controls") {
                ControlEditorView(manager: manager)
            }

            Card(title: "Diagnostics") {
                SettingRow(
                    title: "Verbose logging",
                    subtitle: "Print detailed events (visible in Console.app or when run from a terminal)."
                ) {
                    Toggle("", isOn: $settings.verboseLogging)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }

            Card(title: "About") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 9) {
                        GemMark(size: 24)
                        Text("Quiver").font(.system(size: 17, weight: .semibold))
                    }
                    Text(appVersion).font(.caption).foregroundStyle(.secondary)
                    Text("A menu-bar hub for small Mac utilities you can flip on and off.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Divider().padding(.vertical, 2)
                    Text("Includes the AutoRaise engine by sbmpost, licensed under GPLv3. Quiver is distributed under the GPLv3 — see LICENSE.md.")
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Card(title: "Menu Bar Icon") {
                Text("Choose the icon Quiver shows in the menu bar, or keep the gem. Resize and nudge it to taste.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                IconPicker(
                    selectedSymbol: settings.menuBarIconSymbol,
                    defaultSymbolName: nil,   // the Quiver default is the gem (drawn via GemMark)
                    scale: settings.menuBarIconScale,
                    baselineScale: 1,
                    yOffset: settings.menuBarIconYOffset,
                    isModified: settings.hasCustomMenuBarIcon,
                    onPick: { settings.setMenuBarIconSymbol($0) },
                    onScale: { settings.setMenuBarIconScale($0) },
                    onYOffset: { settings.setMenuBarIconYOffset($0) },
                    onReset: { settings.resetMenuBarIcon() }
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
