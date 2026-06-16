import SwiftUI

private enum SidebarSelection: Hashable {
    case general
    case module(String)
}

/// The main window: a sidebar listing General + every utility, and a detail pane showing the
/// selected utility's full settings (or app-wide General settings).
struct MainWindowView: View {
    @ObservedObject var manager: ModuleManager
    @ObservedObject var settings: AppSettings
    @ObservedObject var uiState: AppUIState
    let onShowSettings: () -> Void

    private var selection: Binding<SidebarSelection?> {
        Binding(
            get: { uiState.selectedModuleID.map(SidebarSelection.module) ?? .general },
            set: { newValue in
                switch newValue {
                case .module(let id): uiState.selectedModuleID = id
                case .general, .none: uiState.selectedModuleID = nil
                }
            }
        )
    }

    var body: some View {
        NavigationSplitView {
            List(selection: selection) {
                Section {
                    Label("General", systemImage: "gearshape")
                        .tag(SidebarSelection.general)
                }
                Section("Utilities") {
                    ForEach(manager.orderedModules) { module in
                        SidebarModuleLabel(module: module)
                            .tag(SidebarSelection.module(module.id))
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            Group {
                if let id = uiState.selectedModuleID, let module = manager.module(id: id) {
                    ModuleDetailView(module: module, manager: manager)
                } else {
                    SettingsView(settings: settings, manager: manager)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct SidebarModuleLabel: View {
    @ObservedObject var module: UtilityModule

    var body: some View {
        HStack {
            Label(module.title, systemImage: module.effectiveSymbolName)
            Spacer()
            if module.isToggleable {
                Circle()
                    .fill(module.isEnabled ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 7, height: 7)
            }
        }
    }
}

/// Header (icon, title, enable toggle, permission) + the module's own settings pane.
struct ModuleDetailView: View {
    @ObservedObject var module: UtilityModule
    @ObservedObject var manager: ModuleManager

    private var isOn: Binding<Bool> {
        Binding(get: { module.isEnabled }, set: { module.setEnabled($0) })
    }

    private var showInMenuBar: Binding<Bool> {
        Binding(get: { manager.isPinned(module.id) }, set: { manager.setPinned(module.id, $0) })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    Image(systemName: module.effectiveSymbolName)
                        .font(.system(size: 26 * module.effectiveSymbolScale, weight: .medium))
                        .offset(y: module.effectiveSymbolYOffset * 2)   // detail icon is ~2× the hub-row size
                        .frame(width: 52, height: 52)
                        .foregroundStyle(module.isEnabled ? Color.accentColor : Color.secondary)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(module.isEnabled ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.10))
                        )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(module.title).font(.title2.bold())
                        Text(module.subtitle).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 10)
                    if module.isToggleable {
                        Toggle("", isOn: isOn)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .disabled(module.permission.unavailableReason != nil)
                    }
                }

                if let reason = module.permission.unavailableReason {
                    Label(reason, systemImage: "nosign")
                        .foregroundStyle(.secondary)
                } else if let needed = module.permission.needed {
                    PermissionBanner(reason: needed.reason, actionTitle: needed.actionTitle) {
                        module.requestPermission()
                    }
                }

                HStack(spacing: 12) {
                    Image(systemName: "menubar.arrow.up.rectangle")
                        .font(.system(size: 15)).foregroundStyle(.secondary).frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show in menu bar").font(.system(size: 13, weight: .medium))
                        Text("Add a dedicated menu-bar icon for quick access to \(module.title).")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 10)
                    Toggle("", isOn: showInMenuBar).labelsHidden().toggleStyle(.switch)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1)
                )

                module.makeSettingsView()

                Card(title: "Icon") {
                    IconPicker(
                        selectedSymbol: module.customSymbolName,
                        defaultSymbolName: module.symbolName,
                        scale: module.customSymbolScale ?? 1,
                        baselineScale: module.iconBaselineScale,
                        yOffset: module.effectiveSymbolYOffset,
                        isModified: module.hasCustomIcon,
                        onPick: { module.setCustomSymbol($0) },
                        onScale: { module.setCustomSymbolScale($0) },
                        onYOffset: { module.setCustomSymbolYOffset($0) },
                        onReset: { module.resetIcon() }
                    )
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
