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

            Card(title: "Menu Bar") {
                Text("Show or hide each utility in the menu, and drag to reorder them.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(manager.orderedModules) { module in
                    HStack(spacing: 10) {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 12)).foregroundStyle(.tertiary)
                        Image(systemName: module.symbolName)
                            .font(.system(size: 13)).frame(width: 20).foregroundStyle(.secondary)
                        Text(module.title).font(.system(size: 13))
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { !manager.isHidden(module.id) },
                            set: { manager.setHidden(module.id, !$0) }
                        ))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    }
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                    .onDrag { NSItemProvider(object: module.id as NSString) }
                    .onDrop(of: [.text], delegate: ModuleReorderDelegate(targetID: module.id, manager: manager))

                    if module.id != manager.orderedModules.last?.id { Divider() }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.82), value: manager.order)
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
                    Text("Quiver").font(.headline)
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
