import SwiftUI

/// A compact row in the menu-bar popover: icon badge, name, one-line status, and a switch
/// (toggleable modules) or a chevron (tools). Tapping the name area opens the module in the main
/// window; detailed controls live there, keeping the popover minimal.
struct ModuleRowView: View {
    @ObservedObject var module: UtilityModule
    let onOpenModule: (String) -> Void

    @State private var hovering = false

    private var isOn: Binding<Bool> {
        Binding(get: { module.isEnabled }, set: { module.setEnabled($0) })
    }

    /// Toggleable modules look "active" when on; tools are neutral.
    private var isActive: Bool { module.isToggleable && module.isEnabled }

    private var needsAttention: Bool {
        module.permission.needed != nil && (module.isToggleable ? module.isEnabled : true)
    }

    var body: some View {
        HStack(spacing: 11) {
            HStack(spacing: 11) {
                Image(systemName: module.symbolName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isActive ? Color.white : Color.secondary)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isActive ? Color.accentColor : Color.primary.opacity(0.06))
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(module.title).font(.system(size: 13, weight: .semibold))
                    HStack(spacing: 4) {
                        if needsAttention {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 9)).foregroundStyle(.orange)
                        }
                        Text(module.statusSummary)
                            .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
            }
            .contentShape(Rectangle())
            .onTapGesture { onOpenModule(module.id) }

            if module.isToggleable {
                Toggle("", isOn: isOn)
                    .labelsHidden().toggleStyle(QuiverSwitchStyle())
                    .disabled(module.permission.unavailableReason != nil)
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(hovering ? Color.primary.opacity(0.05) : Color.clear)
        .onHover { hovering = $0 }
    }
}

/// A switch drawn from explicit shapes/colors instead of the native `NSSwitch`. Inside the menu the
/// native switch is at the mercy of vibrancy (its "on" fill desaturates to white); drawing it ourselves
/// with a concrete accent fill makes the on/off color deterministic. Pairs with the non-vibrant hosting
/// view so the accent isn't blended away.
struct QuiverSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View { SwitchBody(configuration: configuration) }

    struct SwitchBody: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let on = configuration.isOn
            // A Button (not onTapGesture) so the click is reliably consumed inside the menu's modal
            // event loop — otherwise the click falls through and dismisses the menu without toggling.
            Button { configuration.isOn.toggle() } label: {
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(on ? Color.accentColor : Color(nsColor: .tertiaryLabelColor))
                        .frame(width: 28, height: 16)
                    Circle()
                        .fill(.white)
                        .frame(width: 12, height: 12)
                        .shadow(color: .black.opacity(0.20), radius: 0.7, y: 0.4)
                        .offset(x: on ? 14 : 2)
                }
                .opacity(isEnabled ? 1 : 0.5)
                .animation(.easeInOut(duration: 0.15), value: on)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
        }
    }
}
