import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Drawer content (hosted in the borderless edge window)

struct ShelfDrawerContent: View {
    @ObservedObject var store: ShelfStore
    let columns: Int
    let onClear: () -> Void
    let onClose: () -> Void

    @State private var targeted = false

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.fixed(ShelfMetrics.tile.width), spacing: ShelfMetrics.spacing), count: columns)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.35)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(targeted ? Color.accentColor : Color.white.opacity(0.10),
                              lineWidth: targeted ? 2 : 1)
        )
        .onDrop(of: [UTType.fileURL], isTargeted: $targeted) { providers in handleDrop(providers) }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "tray.full").font(.system(size: 11)).foregroundStyle(.secondary)
            Text(store.isEmpty ? "Shelf" : "\(store.count)")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Spacer()
            if !store.isEmpty {
                Button(action: onClear) { Image(systemName: "trash") }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary).help("Clear all")
            }
            Button(action: onClose) { Image(systemName: "xmark") }
                .buttonStyle(.plain).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).help("Hide")
        }
        .padding(.horizontal, 12)
        .frame(height: ShelfMetrics.headerHeight)
    }

    @ViewBuilder
    private var content: some View {
        if store.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "tray.and.arrow.down").font(.system(size: 24)).foregroundStyle(.secondary)
                Text("Drag files here").font(.caption.weight(.medium))
                Text("then drag them back out").font(.caption2).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(8)
        } else {
            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: ShelfMetrics.spacing) {
                    ForEach(store.items) { item in
                        ShelfTileView(item: item, onRemove: { store.remove(item) })
                    }
                }
                .padding(ShelfMetrics.padding)
            }
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

// MARK: - File tile

private struct ShelfTileView: View {
    let item: ShelfItem
    let onRemove: () -> Void

    @State private var thumb: NSImage?

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.07))
                if let thumb {
                    Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fit).padding(6)
                } else {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                        .resizable().aspectRatio(contentMode: .fit).frame(width: 38, height: 38)
                }
            }
            .frame(width: ShelfMetrics.tile.width, height: 64)

            Text(item.displayName)
                .font(.system(size: 10)).lineLimit(1).truncationMode(.middle)
                .frame(width: ShelfMetrics.tile.width)
        }
        .frame(width: ShelfMetrics.tile.width, height: ShelfMetrics.tile.height)
        .contentShape(Rectangle())
        // The AppKit handle covers the whole tile: left-drag = drag the file out, right-click = menu.
        .overlay(FileDragHandle(url: item.url, onRemove: onRemove))
        .help("Drag out to move/copy · right-click for options")
        .task(id: item.url) {
            thumb = await ThumbnailLoader.thumbnail(for: item.url)
        }
    }
}

// MARK: - AppKit drag source (drag a file out + right-click menu)

private struct FileDragHandle: NSViewRepresentable {
    let url: URL
    let onRemove: () -> Void

    func makeNSView(context: Context) -> NSView { DragSourceView(url: url, onRemove: onRemove) }
    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? DragSourceView else { return }
        view.url = url
        view.onRemove = onRemove
    }
}

private final class DragSourceView: NSView, NSDraggingSource {
    var url: URL
    var onRemove: () -> Void
    private var mouseDownPoint: NSPoint?

    init(url: URL, onRemove: @escaping () -> Void) {
        self.url = url
        self.onRemove = onRemove
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override func mouseDown(with event: NSEvent) { mouseDownPoint = event.locationInWindow }
    override func mouseUp(with event: NSEvent) { mouseDownPoint = nil }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint else { return }
        let p = event.locationInWindow
        guard hypot(p.x - start.x, p.y - start.y) >= 4 else { return }   // small threshold
        mouseDownPoint = nil

        let dragItem = NSDraggingItem(pasteboardWriter: url as NSURL)
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 48, height: 48)
        dragItem.setDraggingFrame(NSRect(x: bounds.midX - 24, y: bounds.midY - 24, width: 48, height: 48), contents: icon)
        beginDraggingSession(with: [dragItem], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy   // copy the file out (non-destructive)
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
    /// Returns a real preview for image/PDF files; nil for everything else (the tile then shows the
    /// file-type icon). Loads off the main thread and skips very large files.
    static func thumbnail(for url: URL) async -> NSImage? {
        guard
            let type = UTType(filenameExtension: url.pathExtension),
            type.conforms(to: .image) || type.conforms(to: .pdf)
        else { return nil }

        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 25_000_000 {
            return nil
        }
        return await Task.detached(priority: .utility) { NSImage(contentsOf: url) }.value
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
