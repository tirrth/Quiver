import SwiftUI

/// A single utility's row inside the menu-bar popover: icon, name, status, an on/off toggle,
/// an inline permission banner, and (when enabled) the module's quick controls.
struct ModuleRowView: View {
    @ObservedObject var module: UtilityModule
    let onOpenModule: (String) -> Void

    private var isOn: Binding<Bool> {
        Binding(get: { module.isEnabled }, set: { module.setEnabled($0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: module.symbolName)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 26, height: 26)
                    .foregroundStyle(module.isEnabled ? Color.accentColor : Color.secondary)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(module.isEnabled ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.10))
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(module.title).font(.system(size: 13, weight: .semibold))
                    Text(module.statusSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Toggle("", isOn: isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(module.permission.unavailableReason != nil)
            }
            .contentShape(Rectangle())
            .onTapGesture { onOpenModule(module.id) }

            if let reason = module.permission.unavailableReason {
                Label(reason, systemImage: "nosign")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if module.isEnabled, let needed = module.permission.needed {
                PermissionBanner(reason: needed.reason, actionTitle: needed.actionTitle) {
                    module.requestPermission()
                }
            }

            if module.isEnabled, module.permission.isOK, let controls = module.makeQuickControls() {
                controls
                    .padding(.leading, 36)
            }
        }
        .padding(.vertical, 6)
    }
}
