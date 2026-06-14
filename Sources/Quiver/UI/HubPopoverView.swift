import SwiftUI

/// The menu-bar popover — compact and minimal: a tidy header, one row per utility, and a slim footer.
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
            Divider().opacity(0.6)

            VStack(spacing: 1) {
                ForEach(manager.modules) { module in
                    ModuleRowView(module: module, onOpenModule: onOpenModule)
                }
            }
            .padding(.vertical, 5)

            Divider().opacity(0.6)
            footer
        }
        .frame(width: 290)
        .fixedSize(horizontal: false, vertical: true)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 13, weight: .bold)).foregroundStyle(Color.accentColor)
            Text("Quiver").font(.system(size: 14, weight: .bold))
            Spacer()
            IconButton(symbol: "gearshape", help: "Settings", action: onOpenSettings)
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button(action: onOpenApp) {
                Label("Open Quiver", systemImage: "macwindow")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            Spacer()
            IconButton(symbol: "power", help: "Quit Quiver", action: onQuit)
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
    }
}

/// A subtle ghost icon button used in the popover chrome.
private struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(hover ? Color.primary : Color.secondary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(hover ? Color.primary.opacity(0.08) : Color.clear))
        }
        .buttonStyle(.plain).help(help).onHover { hover = $0 }
    }
}
