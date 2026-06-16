import SwiftUI

/// Shown when you left-click a pinned utility's menu-bar icon: a header with its on/off toggle, the
/// utility's own quick controls, and a footer to open it in Quiver or unpin it.
struct PinnedControlsView: View {
    @ObservedObject var module: UtilityModule
    let onOpenInQuiver: () -> Void
    let onRemove: () -> Void

    private var isOn: Binding<Bool> {
        Binding(get: { module.isEnabled }, set: { module.setEnabled($0) })
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: module.effectiveSymbolName)
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary).frame(width: 22)
                Text(module.title).font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 8)
                if module.isToggleable {
                    Toggle("", isOn: isOn)
                        .labelsHidden().toggleStyle(QuiverSwitchStyle())
                        .disabled(module.permission.unavailableReason != nil)
                }
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 10)

            if let needed = module.permission.needed {
                PermissionBanner(reason: needed.reason, actionTitle: needed.actionTitle) {
                    module.requestPermission()
                }
                .padding(.horizontal, 12).padding(.bottom, 10)
            }

            if let controls = module.makeQuickControls() {
                Divider()
                controls.padding(14)
            }

            Divider()
            HStack(spacing: 12) {
                Button(action: onOpenInQuiver) {
                    Label("Open in Quiver", systemImage: "macwindow").font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                Spacer()
                Button(action: onRemove) {
                    Label("Unpin", systemImage: "pin.slash").font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
        }
        .frame(width: 300)
    }
}
