import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Drawer content (hosted in the borderless edge window)

struct ShelfDrawerContent: View {
    @ObservedObject var store: ShelfStore
    let edge: ShelfEdge
    let columns: Int
    let onClear: () -> Void
    let onClose: () -> Void

    @State private var targeted = false

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.fixed(ShelfMetrics.tile.width), spacing: ShelfMetrics.spacing), count: columns)
    }

    /// Rounded only on the inner side; flat on the side touching the screen edge.
    private var shape: UnevenRoundedRectangle {
        let r = ShelfMetrics.cornerRadius
        switch edge {
        case .right:  return .init(topLeadingRadius: r, bottomLeadingRadius: r, bottomTrailingRadius: 0, topTrailingRadius: 0, style: .continuous)
        case .left:   return .init(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: r, topTrailingRadius: r, style: .continuous)
        case .top:    return .init(topLeadingRadius: 0, bottomLeadingRadius: r, bottomTrailingRadius: r, topTrailingRadius: 0, style: .continuous)
        case .bottom: return .init(topLeadingRadius: r, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: r, style: .continuous)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.3)
            content
            if !store.isEmpty {
                Divider().opacity(0.3)
                footer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .clipShape(shape)
        .overlay(
            shape.strokeBorder(targeted ? Color.accentColor : Color.primary.opacity(0.10),
                               lineWidth: targeted ? 2 : 1)
        )
        .animation(.easeOut(duration: 0.15), value: targeted)
        .animation(.spring(response: 0.3, dampingFraction: 0.74), value: store.isEmpty)
        .onDrop(of: [UTType.fileURL], isTargeted: $targeted) { providers in handleDrop(providers) }
    }

    private var header: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.accentColor.gradient)
                Image(systemName: "tray.full.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
            }
            .frame(width: 32, height: 32)
            .shadow(color: Color.accentColor.opacity(0.35), radius: 5, y: 2)

            VStack(alignment: .leading, spacing: 1) {
                Text("Shelf").font(.system(size: 14.5, weight: .bold))
                Text(store.isEmpty ? "Empty" : "\(store.count) file\(store.count == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            }
            Spacer()
            if !store.isEmpty {
                CircleIconButton(symbol: "trash", help: "Clear all", action: onClear)
            }
            CircleIconButton(symbol: "xmark", help: "Hide", action: onClose)
        }
        .padding(.horizontal, 16)
        .frame(height: ShelfMetrics.headerHeight)
    }

    private var footer: some View {
        HStack(spacing: 5) {
            Image(systemName: "hand.draw").font(.system(size: 9))
            Text("Drag a tile out · right-click for options").font(.system(size: 9.5, weight: .medium))
        }
        .foregroundStyle(.tertiary)
        .frame(height: ShelfMetrics.footerHeight)
    }

    @ViewBuilder
    private var content: some View {
        if store.isEmpty {
            VStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                        .foregroundStyle(targeted ? Color.accentColor : Color.secondary.opacity(0.4))
                        .frame(width: 80, height: 64)
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 24)).foregroundStyle(targeted ? Color.accentColor : .secondary)
                }
                Text("Drag files here").font(.system(size: 12.5, weight: .semibold))
                Text("then switch windows and drag them back out")
                    .font(.system(size: 10.5)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(14)
            .transition(.opacity)
        } else {
            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: ShelfMetrics.spacing) {
                    ForEach(store.items) { item in
                        ShelfTileView(item: item, onRemove: { store.remove(item) })
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.55).combined(with: .opacity),
                                removal: .scale(scale: 0.82).combined(with: .opacity)
                            ))
                    }
                }
                .padding(ShelfMetrics.padding)
                .animation(.spring(response: 0.34, dampingFraction: 0.74), value: store.items)
            }
            .scrollIndicators(.never)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let store = self.store
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                var url: URL?
                if let data = data as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                else if let u = data as? URL { url = u }
                if let url, url.isFileURL { DispatchQueue.main.async { store.add(urls: [url]) } }
            }
        }
        return !providers.isEmpty
    }
}

// MARK: - Circular ghost button (header actions)

private struct CircleIconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Color.primary.opacity(hover ? 0.15 : 0.07)).frame(width: 26, height: 26)
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
    }
}

// MARK: - File tile (elevated card)

private struct ShelfTileView: View {
    let item: ShelfItem
    let onRemove: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var thumb: NSImage?
    @State private var hovering = false

    private var dark: Bool { scheme == .dark }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(
                        colors: [dark ? Color.white.opacity(0.13) : Color.white,
                                 dark ? Color.white.opacity(0.04) : Color(white: 0.965)],
                        startPoint: .top, endPoint: .bottom))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(dark ? Color.white.opacity(0.09) : Color.black.opacity(0.05), lineWidth: 1)
                    )

                if let thumb {
                    Image(nsImage: thumb)
                        .resizable().aspectRatio(contentMode: .fill)
                        .frame(width: ShelfMetrics.cardWidth - 16, height: ShelfMetrics.previewHeight - 16)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                        .resizable().aspectRatio(contentMode: .fit).padding(16)
                }
            }
            .frame(width: ShelfMetrics.cardWidth, height: ShelfMetrics.previewHeight)
            .shadow(color: dark ? Color.black.opacity(0.34) : Color.black.opacity(hovering ? 0.18 : 0.11),
                    radius: hovering ? 8 : 6, x: 0, y: hovering ? 4 : 3)

            Text(item.displayName)
                .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                .lineLimit(2).multilineTextAlignment(.center).truncationMode(.middle)
                .frame(width: ShelfMetrics.tile.width, height: ShelfMetrics.nameHeight, alignment: .top)
        }
        .frame(width: ShelfMetrics.tile.width, height: ShelfMetrics.tile.height)
        .scaleEffect(hovering ? 1.05 : 1.0)
        .animation(.easeOut(duration: 0.13), value: hovering)
        .contentShape(Rectangle())
        // Whole tile is the AppKit handle: left-drag = drag file out, right-click = menu, hover = lift.
        .overlay(FileDragHandle(url: item.url, onRemove: onRemove, onHoverChange: { hovering = $0 }))
        .help("Drag out to move/copy · right-click for options")
        .task(id: item.url) { thumb = await ThumbnailLoader.thumbnail(for: item.url) }
    }
}

// MARK: - AppKit drag source (drag out + right-click menu + hover)

private struct FileDragHandle: NSViewRepresentable {
    let url: URL
    let onRemove: () -> Void
    let onHoverChange: (Bool) -> Void

    func makeNSView(context: Context) -> NSView {
        DragSourceView(url: url, onRemove: onRemove, onHoverChange: onHoverChange)
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? DragSourceView else { return }
        view.url = url
        view.onRemove = onRemove
        view.onHoverChange = onHoverChange
    }
}

private final class DragSourceView: NSView, NSDraggingSource {
    var url: URL
    var onRemove: () -> Void
    var onHoverChange: (Bool) -> Void
    private var mouseDownPoint: NSPoint?

    init(url: URL, onRemove: @escaping () -> Void, onHoverChange: @escaping (Bool) -> Void) {
        self.url = url
        self.onRemove = onRemove
        self.onHoverChange = onHoverChange
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil
        ))
    }
    override func mouseEntered(with event: NSEvent) { onHoverChange(true) }
    override func mouseExited(with event: NSEvent) { onHoverChange(false) }

    override func mouseDown(with event: NSEvent) { mouseDownPoint = event.locationInWindow }
    override func mouseUp(with event: NSEvent) { mouseDownPoint = nil }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint else { return }
        let p = event.locationInWindow
        guard hypot(p.x - start.x, p.y - start.y) >= 4 else { return }
        mouseDownPoint = nil

        let dragItem = NSDraggingItem(pasteboardWriter: url as NSURL)
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 64, height: 64)
        dragItem.setDraggingFrame(NSRect(x: bounds.midX - 32, y: bounds.midY - 32, width: 64, height: 64), contents: icon)
        beginDraggingSession(with: [dragItem], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let remove = NSMenuItem(title: "Remove from Shelf", action: #selector(removeItem), keyEquivalent: "")
        remove.target = self
        menu.addItem(remove)
        let reveal = NSMenuItem(title: "Reveal in Finder", action: #selector(reveal), keyEquivalent: "")
        reveal.target = self
        menu.addItem(reveal)
        return menu
    }
    @objc private func removeItem() { onRemove() }
    @objc private func reveal() { NSWorkspace.shared.activateFileViewerSelecting([url]) }
}

// MARK: - Thumbnails (native image/PDF previews, icon fallback otherwise)

enum ThumbnailLoader {
    @MainActor
    static func thumbnail(for url: URL) async -> NSImage? {
        guard
            let type = UTType(filenameExtension: url.pathExtension),
            type.conforms(to: .image) || type.conforms(to: .pdf)
        else { return nil }

        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 25_000_000 {
            return nil
        }
        let data = await Task.detached(priority: .utility) { try? Data(contentsOf: url) }.value
        return data.flatMap(NSImage.init(data:))
    }
}

// MARK: - Popover quick controls

struct ShelfQuickControls: View {
    @ObservedObject var module: ShelfModule

    var body: some View {
        HStack(spacing: 8) {
            Button { module.openShelf() } label: { Label("Open shelf", systemImage: "tray.full") }
                .controlSize(.small)
            Spacer()
            Text(module.controller.store.isEmpty ? "empty" : "\(module.controller.store.count) held")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Settings pane

struct ShelfSettingsView: View {
    @ObservedObject var module: ShelfModule

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Card(title: "Behavior") {
                SettingRow(
                    title: "Pop out when I start dragging files",
                    subtitle: "The shelf slides out automatically as soon as you begin dragging files. Turn off to open it only from the menu."
                ) {
                    Toggle("", isOn: Binding(
                        get: { module.controller.autoPop },
                        set: { module.controller.setAutoPop($0); module.notifyChange() }
                    )).labelsHidden().toggleStyle(.switch)
                }

                Divider()

                SettingRow(
                    title: "Slides out from",
                    subtitle: "Which screen edge the shelf drawer appears from (on whichever display your pointer is on)."
                ) {
                    Picker("", selection: Binding(
                        get: { module.controller.edge },
                        set: { module.controller.setEdge($0); module.notifyChange() }
                    )) {
                        ForEach(ShelfEdge.allCases) { edge in
                            Text(edge.label).tag(edge)
                        }
                    }
                    .labelsHidden().frame(width: 130)
                }
            }

            Card(title: "Shelf") {
                HStack {
                    Button { module.openShelf() } label: { Label("Open shelf now", systemImage: "tray.full") }
                    Spacer()
                    Text(module.controller.store.isEmpty ? "Empty" : "\(module.controller.store.count) item(s)")
                        .foregroundStyle(.secondary)
                }
                Text("Drop files on the shelf, then drag a tile back out to move/copy it. Right-click a tile to remove it or reveal it in Finder. The drawer floats above everything and follows you across Spaces.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
