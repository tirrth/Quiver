import SwiftUI

/// The menu-bar popover — Quiver's primary control surface. Lists every utility with a toggle and
/// inline quick controls, plus a footer to open the full app, settings, or quit.
struct HubPopoverView: View {
    @ObservedObject var manager: ModuleManager
    @ObservedObject var settings: AppSettings

    let onOpenApp: () -> Void
    let onOpenModule: (String) -> Void
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(manager.modules.enumerated()), id: \.element.id) { index, module in
                        ModuleRowView(module: module, onOpenModule: onOpenModule)
                            .padding(.horizontal, 14)
                        if index < manager.modules.count - 1 {
                            Divider().padding(.leading, 50)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Divider()
            footer
        }
        .frame(width: 360)
        .frame(maxHeight: 520)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text("Quiver").font(.system(size: 14, weight: .bold))
                Text("\(manager.enabledCount) of \(manager.modules.count) on")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button(action: onOpenApp) {
                Label("Open Quiver", systemImage: "macwindow")
            }
            .buttonStyle(.borderless)

            Spacer()

            Button(action: onQuit) {
                Label("Quit", systemImage: "power")
            }
            .buttonStyle(.borderless)
            .help("Quit Quiver completely")
        }
        .font(.system(size: 12))
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}
