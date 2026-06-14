import SwiftUI
import UniformTypeIdentifiers

/// The menu-bar popover — compact and minimal: a tidy header, one row per utility, and a slim footer.
struct HubPopoverView: View {
    @ObservedObject var manager: ModuleManager
    @ObservedObject var settings: AppSettings

    let onOpenApp: () -> Void
    let onOpenModule: (String) -> Void
    let onOpenSettings: () -> Void
    let onQuit: () -> Void
    /// When hosted inside an NSMenu the menu supplies its own background/rounding, so we drop our
    /// own card chrome to avoid a doubled material.
    var inMenu: Bool = false

    var body: some View {
        if inMenu {
            content
        } else {
            content
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.6)

            VStack(spacing: 1) {
                ForEach(manager.menuModules) { module in
                    ModuleRowView(module: module, onOpenModule: onOpenModule)
                        .onDrag { NSItemProvider(object: module.id as NSString) }
                        .onDrop(of: [.text], delegate: ModuleReorderDelegate(targetID: module.id, manager: manager))
                }
            }
            .padding(.vertical, 5)
            .animation(.spring(response: 0.3, dampingFraction: 0.82), value: manager.order)

            Divider().opacity(0.6)
            footer
        }
        .frame(width: 290)
        .fixedSize(horizontal: false, vertical: true)
        // When hosted in the NSMenu, the window focuses the first control (the gear) and macOS draws
        // its keyboard focus ring, which looks like a stuck highlight. The hub is mouse-driven, so
        // suppress the focus effect for the whole popover.
        .noFocusRing()
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrowshape.up.fill")
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

/// Drag-and-drop reordering of module tiles — shared by the menu-bar hub and the settings list.
struct ModuleReorderDelegate: DropDelegate {
    let targetID: String
    let manager: ModuleManager

    func dropEntered(info: DropInfo) {
        guard let provider = info.itemProviders(for: [.text]).first else { return }
        _ = provider.loadObject(ofClass: NSString.self) { obj, _ in
            guard let dragged = obj as? String, dragged != targetID else { return }
            Task { @MainActor in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { manager.move(dragged, before: targetID) }
            }
        }
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool { true }
}

private extension View {
    /// Suppresses the keyboard focus ring (macOS 14+). No-op on macOS 13.
    @ViewBuilder func noFocusRing() -> some View {
        if #available(macOS 14.0, *) { focusEffectDisabled() } else { self }
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
