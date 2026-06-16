import SwiftUI

/// The menu-bar hub, styled like Control Center: a glassy grid of resizable module tiles with a tidy
/// header and footer, plus an in-place Edit mode (rearrange, resize, add, remove).
struct HubGridView: View {
    @ObservedObject var manager: ModuleManager
    @ObservedObject var settings: AppSettings

    let onOpenApp: () -> Void
    let onOpenModule: (String) -> Void
    let onOpenSettings: () -> Void
    let onQuit: () -> Void
    /// Called when the content's height changes so the host can re-measure the NSMenu item.
    var onResize: (() -> Void)?
    /// Hosted inside an NSMenu — the menu supplies the background/rounding, so we drop our own card chrome.
    var inMenu: Bool = false

    @State private var editing = false

    // Control Center sizing: a 295pt-wide grid of 65pt tiles, 4 across; the 35pt remainder is split
    // into the 3 inter-tile gaps (≈11.67pt each), so the tiles sit flush to the 295pt content edges.
    private let columns = 4
    private let hubWidth: CGFloat = 295
    private let tileSide: CGFloat = 65
    private var tileSpacing: CGFloat { (hubWidth - tileSide * CGFloat(columns)) / CGFloat(columns - 1) }

    var body: some View {
        // No enclosing container — like Control Center, the tiles and chrome float on the desktop.
        // The padding gives the drop shadow room around each floating element.
        content
            .padding(12)
            .environment(\.colorScheme, .dark)   // white text/icons like Control Center
            // Re-measure the host whenever the content height changes (edit toggled, resize, add/remove).
            .background(GeometryReader { proxy in
                Color.clear.onChange(of: proxy.size.height) { _ in onResize?() }
            })
    }

    private var content: some View {
        VStack(spacing: 10) {
            header
            grid
            if editing { addTray }
            footer
        }
        .frame(width: hubWidth)
        .fixedSize(horizontal: false, vertical: true)
        .ccNoFocusRing()
    }

    @ViewBuilder private var grid: some View {
        if manager.menuModules.isEmpty {
            Text(editing ? "Add controls from below." : "No controls yet — tap Edit to add some.")
                .font(.callout).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity).padding(.vertical, 24)
        } else {
            TileGridLayout(columns: columns, spacing: tileSpacing) {
                ForEach(manager.menuModules) { module in
                    let size = manager.tileSize(module.id)
                    Group {
                        if editing {
                            HubEditTile(module: module, size: size, manager: manager)
                        } else {
                            ModuleTile(module: module, size: size, onOpenModule: onOpenModule)
                        }
                    }
                    .tileSpan(size.cells.w, size.cells.h)
                    .modifier(ReorderDrag(id: module.id, manager: manager, enabled: editing))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.82), value: manager.order)
            .animation(.spring(response: 0.3, dampingFraction: 0.82), value: manager.tileSizes)
        }
    }

    private var addTray: some View {
        let hidden = manager.orderedModules.filter { manager.isHidden($0.id) }
        return Group {
            if !hidden.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("ADD CONTROLS").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary).tracking(0.6)
                    let cols = [GridItem(.adaptive(minimum: 132), spacing: 6)]
                    LazyVGrid(columns: cols, alignment: .leading, spacing: 6) {
                        ForEach(hidden) { module in
                            Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { manager.setHidden(module.id, false) } } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: module.effectiveSymbolName).font(.system(size: 11)).frame(width: 16).foregroundStyle(.secondary)
                                    Text(module.title).font(.system(size: 11)).lineLimit(1)
                                    Spacer(minLength: 2)
                                    Image(systemName: "plus.circle.fill").font(.system(size: 11)).foregroundStyle(Color.accentColor)
                                }
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .ccGlassCapsule()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 12).padding(.bottom, 10)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            GemMark(size: 22)
            Text("Quiver").font(.system(size: 15, weight: .bold))
            Spacer()
            Button(editing ? "Done" : "Edit") { withAnimation { editing.toggle() } }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: editing ? .semibold : .regular))
                .foregroundStyle(editing ? Color.accentColor : .secondary)
            CCIconButton(symbol: "gearshape", help: "Settings", action: onOpenSettings)
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .shadow(color: .black.opacity(0.28), radius: 1.5, y: 0.5)
        .ccGlassCapsule()
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button(action: onOpenApp) {
                Label("Open Quiver", systemImage: "macwindow").font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            Spacer()
            CCIconButton(symbol: "power", help: "Quit Quiver", action: onQuit)
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
        .shadow(color: .black.opacity(0.28), radius: 1.5, y: 0.5)
        .ccGlassCapsule()
    }
}

/// Reorder-by-drag, only active in edit mode (drag works inside the NSMenu).
private struct ReorderDrag: ViewModifier {
    let id: String
    let manager: ModuleManager
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled {
            content
                .onDrag { NSItemProvider(object: id as NSString) }
                .onDrop(of: [.text], delegate: ModuleReorderDelegate(targetID: id, manager: manager))
        } else {
            content
        }
    }
}

/// An in-hub edit tile: the face plus a remove badge and a tap-to-cycle size badge.
struct HubEditTile: View {
    @ObservedObject var module: UtilityModule
    let size: TileSize
    @ObservedObject var manager: ModuleManager

    var body: some View {
        ModuleTileFace(module: module, size: size, interactive: false)
            .overlay(alignment: .topLeading) {
                Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { manager.setHidden(module.id, true) } } label: {
                    Image(systemName: "minus.circle.fill").font(.system(size: 15))
                        .symbolRenderingMode(.palette).foregroundStyle(.white, Color.red)
                }
                .buttonStyle(.plain).offset(x: -5, y: -5).help("Remove")
            }
            .overlay(alignment: .bottomTrailing) {
                Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { manager.setTileSize(module.id, size.next) } } label: {
                    Image(systemName: "square.resize").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary).frame(width: 18, height: 18)
                        .background(Circle().fill(.regularMaterial))
                }
                .buttonStyle(.plain).offset(x: -3, y: -3).help("Resize (\(size.label))")
            }
    }
}

/// A subtle ghost icon button used in the hub chrome.
struct CCIconButton: View {
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

extension View {
    /// Suppresses the keyboard focus ring (macOS 14+). No-op on macOS 13.
    @ViewBuilder func ccNoFocusRing() -> some View {
        if #available(macOS 14.0, *) { focusEffectDisabled() } else { self }
    }
}
