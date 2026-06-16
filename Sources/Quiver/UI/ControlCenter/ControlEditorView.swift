import SwiftUI

/// The Control-Center "Customize" surface, embedded in the main window: a live tile grid you can
/// drag to rearrange, drag a corner to resize (small → wide → large), plus a gallery of more controls
/// to add. The hub mirrors this immediately (shared `ModuleManager` state).
struct ControlEditorView: View {
    @ObservedObject var manager: ModuleManager

    private let columns = 4
    private let cellSide: CGFloat = 76
    private let spacing: CGFloat = 12
    private var gridWidth: CGFloat { CGFloat(columns) * cellSide + spacing * CGFloat(columns - 1) }

    private var galleryModules: [UtilityModule] { manager.orderedModules.filter { manager.isHidden($0.id) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Drag to rearrange, drag a tile's corner to resize, and add or remove controls. Your menu-bar Quiver mirrors this.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            if manager.menuModules.isEmpty {
                Text("No controls yet — add some from the gallery below.")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: gridWidth, minHeight: 80)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
            } else {
                TileGridLayout(columns: columns, spacing: spacing) {
                    ForEach(manager.menuModules) { module in
                        let size = manager.tileSize(module.id)
                        EditableTile(module: module, size: size, manager: manager, cellSide: cellSide)
                            .tileSpan(size.cells.w, size.cells.h)
                            .onDrag { NSItemProvider(object: module.id as NSString) }
                            .onDrop(of: [.text], delegate: ModuleReorderDelegate(targetID: module.id, manager: manager))
                    }
                }
                .frame(width: gridWidth)
                .coordinateSpace(name: "editorGrid")
                .animation(.spring(response: 0.32, dampingFraction: 0.82), value: manager.order)
                .animation(.spring(response: 0.32, dampingFraction: 0.82), value: manager.tileSizes)
            }

            if !galleryModules.isEmpty {
                Text("MORE CONTROLS")
                    .font(.caption2.weight(.semibold)).foregroundStyle(.secondary).tracking(0.6)
                    .padding(.top, 4)
                gallery
            }
        }
    }

    private var gallery: some View {
        let columns = [GridItem(.adaptive(minimum: 150), spacing: 10)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(galleryModules) { module in
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { manager.setHidden(module.id, false) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: module.effectiveSymbolName).font(.system(size: 13)).frame(width: 20).foregroundStyle(.secondary)
                        Text(module.title).font(.system(size: 12)).lineLimit(1)
                        Spacer(minLength: 4)
                        Image(systemName: "plus.circle.fill").font(.system(size: 13)).foregroundStyle(Color.accentColor)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.05)))
                }
                .buttonStyle(.plain)
                .help("Add \(module.title) to Quiver")
            }
        }
        .frame(maxWidth: gridWidth)
    }
}

/// A tile in the editor: the tile face plus edit affordances (remove, pin, corner-resize).
struct EditableTile: View {
    @ObservedObject var module: UtilityModule
    let size: TileSize
    @ObservedObject var manager: ModuleManager
    let cellSide: CGFloat

    var body: some View {
        ModuleTileFace(module: module, size: size, interactive: false)
            .overlay(alignment: .topLeading) { removeBadge }
            .overlay(alignment: .topTrailing) { pinBadge }
            .overlay(alignment: .bottomTrailing) { resizeHandle }
    }

    private var removeBadge: some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { manager.setHidden(module.id, true) }
        } label: {
            Image(systemName: "minus.circle.fill")
                .font(.system(size: 16)).symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color.red)
        }
        .buttonStyle(.plain).offset(x: -6, y: -6).help("Remove from Quiver")
    }

    private var pinBadge: some View {
        let pinned = manager.isPinned(module.id)
        return Button { manager.setPinned(module.id, !pinned) } label: {
            Image(systemName: pinned ? "pin.circle.fill" : "pin.circle")
                .font(.system(size: 15))
                .foregroundStyle(pinned ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain).offset(x: 6, y: -6)
        .help(pinned ? "Has its own menu-bar icon" : "Give it its own menu-bar icon")
    }

    /// Corner drag-resize. Uses the stable "editorGrid" coordinate space so live reflow doesn't make
    /// the gesture jitter: right → wide, right+down → large, otherwise small.
    private var resizeHandle: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.secondary)
            .frame(width: 18, height: 18)
            .background(Circle().fill(.regularMaterial))
            .offset(x: -3, y: -3)
            .gesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .named("editorGrid"))
                    .onChanged { value in
                        let dx = value.location.x - value.startLocation.x
                        let dy = value.location.y - value.startLocation.y
                        let wide = dx > cellSide * 0.5
                        let tall = dy > cellSide * 0.5
                        let target: TileSize = (wide && tall) ? .large : (wide ? .wide : .small)
                        if target != manager.tileSize(module.id) { manager.setTileSize(module.id, target) }
                    }
            )
            .help("Drag to resize")
    }
}
