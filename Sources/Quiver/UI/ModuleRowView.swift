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

/// A switch drawn from explicit shapes so its on/off color is deterministic. The native `NSSwitch`
/// can't be used inside the hub: an NSMenu is vibrant, and vibrancy desaturates the native switch's
/// accent "on" fill to white (non-deterministically, per draw). This matches the native look (accent
/// capsule + white knob) while guaranteeing the color. Uses a `Button`, not `onTapGesture`, so the
/// click is consumed inside the menu's modal event loop (toggles without dismissing the menu).
struct QuiverSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View { SwitchBody(configuration: configuration) }

    struct SwitchBody: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let on = configuration.isOn
            Button { configuration.isOn.toggle() } label: {
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(on ? Color.accentColor : Color(nsColor: .quaternaryLabelColor))
                        .frame(width: 40, height: 20)
                    Circle()
                        .fill(LinearGradient(colors: [.white, Color(white: 0.96)], startPoint: .top, endPoint: .bottom))
                        .frame(width: 14, height: 14)
                        .shadow(color: .black.opacity(0.13), radius: 1, y: 0.5)
                        .offset(x: on ? 23 : 3)
                }
                .frame(width: 40, height: 20)
                .animation(.easeInOut(duration: 0.18), value: on)
                .opacity(isEnabled ? 1 : 0.5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
        }
    }
}
