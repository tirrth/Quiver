import SwiftUI

/// A single utility's row inside the menu-bar popover: icon, name, status, an on/off toggle (or an
/// Open button for "tool" modules), an inline permission banner, and the module's quick controls.
struct ModuleRowView: View {
    @ObservedObject var module: UtilityModule
    let onOpenModule: (String) -> Void

    private var isOn: Binding<Bool> {
        Binding(get: { module.isEnabled }, set: { module.setEnabled($0) })
    }

    /// Toggleable modules look "active" when enabled; tools always read as available.
    private var isActive: Bool { module.isToggleable ? module.isEnabled : true }

    private var showsControls: Bool {
        guard module.permission.isOK else { return false }
        return module.isToggleable ? module.isEnabled : true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: module.symbolName)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 26, height: 26)
                    .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(isActive ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.10))
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(module.title).font(.system(size: 13, weight: .semibold))
                    Text(module.statusSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if module.isToggleable {
                    Toggle("", isOn: isOn)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .disabled(module.permission.unavailableReason != nil)
                } else {
                    Button("Open") { onOpenModule(module.id) }
                        .controlSize(.small)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onOpenModule(module.id) }

            if let reason = module.permission.unavailableReason {
                Label(reason, systemImage: "nosign")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let needed = module.permission.needed,
                      (module.isToggleable ? module.isEnabled : true) {
                PermissionBanner(reason: needed.reason, actionTitle: needed.actionTitle) {
                    module.requestPermission()
                }
            }

            if showsControls, let controls = module.makeQuickControls() {
                controls.padding(.leading, 36)
            }
        }
        .padding(.vertical, 6)
    }
}
