import SwiftUI
import AppKit
import Quartz
import UniformTypeIdentifiers

/// Drives the system Quick Look panel for previewing a shelf item.
@MainActor
final class ShelfQuickLook: NSObject, QLPreviewPanelDataSource {
    static let shared = ShelfQuickLook()
    private var urls: [URL] = []

    func show(_ urls: [URL]) {
        self.urls = urls
        guard let panel = QLPreviewPanel.shared() else { return }
        panel.dataSource = self
        if panel.isVisible { panel.reloadData() } else { panel.makeKeyAndOrderFront(nil) }
    }
    func numberOfPreviewItems(in panel: QLPreviewPanel) -> Int { urls.count }
    func previewPanel(_ panel: QLPreviewPanel, previewItemAt index: Int) -> any QLPreviewItem { urls[index] as NSURL }
}

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
        .onDrop(of: [.fileURL, .image, .url, .text, .plainText], isTargeted: $targeted) { providers in handleDrop(providers) }
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
                Text(store.isEmpty ? "Empty" : "\(store.totalItems) file\(store.totalItems == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            }
            Spacer()
            if !store.isEmpty {
                ShelfActionsMenu(store: store, onClear: onClear)
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
                    ForEach(store.groups) { group in
                        Group {
                            if group.items.count == 1 {
                                ShelfTileView(item: group.items[0], onRemove: { store.removeGroup(group.id) })
                            } else {
                                ShelfStackTileView(group: group,
                                                   onRemove: { store.removeGroup(group.id) },
                                                   onUngroup: { store.ungroup(group.id) })
                            }
                        }
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.55).combined(with: .opacity),
                            removal: .scale(scale: 0.82).combined(with: .opacity)
                        ))
                    }
                }
                .padding(ShelfMetrics.padding)
                .animation(.spring(response: 0.34, dampingFraction: 0.74), value: store.groups)
            }
            .scrollIndicators(.never)
        }
    }

    /// Load everything in one drop, then add it as a single group (so dropping N files at once makes
    /// one stack tile, not N separate tiles).
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        let store = self.store
        let group = DispatchGroup()
        let lock = NSLock()
        var collected: [(Int, ShelfItem)] = []   // (drop order, item)
        func collect(_ index: Int, _ item: ShelfItem?) {
            guard let item else { return }
            lock.lock(); collected.append((index, item)); lock.unlock()
        }

        for (i, provider) in providers.enumerated() {
            group.enter()
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { obj, _ in
                    if let url = Self.url(from: obj), url.isFileURL {
                        collect(i, ShelfItem(kind: Self.isImageFile(url) ? .image : .file, url: url))
                    }
                    group.leave()
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    if let data, let url = ShelfStorage.saveImage(data, ext: "png") {
                        collect(i, ShelfItem(kind: .image, url: url))
                    }
                    group.leave()
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.url.identifier) { obj, _ in
                    if let url = Self.url(from: obj), !url.isFileURL { collect(i, ShelfItem(kind: .link, url: url)) }
                    group.leave()
                }
            } else if provider.canLoadObject(ofClass: NSString.self) {
                _ = provider.loadObject(ofClass: NSString.self) { obj, _ in
                    if let s = (obj as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                        collect(i, Self.item(forText: s))
                    }
                    group.leave()
                }
            } else {
                group.leave()
            }
        }

        group.notify(queue: .main) {
            let items = collected.sorted { $0.0 < $1.0 }.map(\.1)
            if !items.isEmpty { store.addItems(items) }
        }
        return true
    }

    private static func isImageFile(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) ?? false
    }
    private static func item(forText s: String) -> ShelfItem {
        if let url = URL(string: s), let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https", !s.contains(" ") {
            return ShelfItem(kind: .link, url: url)
        }
        return ShelfItem(kind: .text, text: s)
    }

    private static func url(from item: NSSecureCoding?) -> URL? {
        if let data = item as? Data { return URL(dataRepresentation: data, relativeTo: nil) }
        if let url = item as? URL { return url }
        if let s = item as? String { return URL(string: s) }
        return nil
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

/// Header "…" menu — act on the whole shelf at once.
private struct ShelfActionsMenu: View {
    @ObservedObject var store: ShelfStore
    let onClear: () -> Void
    @State private var hover = false

    var body: some View {
        Menu {
            Button { store.copyAllToPasteboard() } label: { Label("Copy All", systemImage: "doc.on.doc") }
            if !store.fileURLs.isEmpty {
                ShareLink(items: store.fileURLs) { Label("Share All…", systemImage: "square.and.arrow.up") }
                Button { store.compressToZip() } label: { Label("Compress to ZIP", systemImage: "archivebox") }
            }
            Divider()
            Button(role: .destructive) { onClear() } label: { Label("Clear All", systemImage: "trash") }
        } label: {
            ZStack {
                Circle().fill(Color.primary.opacity(hover ? 0.15 : 0.07)).frame(width: 26, height: 26)
                Image(systemName: "ellipsis").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 26, height: 26)
        .onHover { hover = $0 }
        .help("Shelf actions")
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
                cardContent
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
        // Whole tile is the AppKit handle: left-drag = drag out, right-click = menu, hover = lift.
        .overlay(FileDragHandle(items: [item], onRemove: onRemove, onUngroup: nil, onHoverChange: { hovering = $0 }))
        .help("Drag out to move/copy · right-click for options")
        .task(id: item.id) {
            if item.kind == .file || item.kind == .image, let u = item.url {
                thumb = await ThumbnailLoader.thumbnail(for: u)
            }
        }
    }

    @ViewBuilder private var cardContent: some View {
        switch item.kind {
        case .file, .image:
            if let thumb {
                Image(nsImage: thumb)
                    .resizable().aspectRatio(contentMode: .fill)
                    .frame(width: ShelfMetrics.cardWidth - 16, height: ShelfMetrics.previewHeight - 16)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else if let u = item.url {
                Image(nsImage: NSWorkspace.shared.icon(forFile: u.path))
                    .resizable().aspectRatio(contentMode: .fit).padding(16)
            }
        case .text:
            Text(item.text ?? "")
                .font(.system(size: 9.5)).foregroundStyle(.secondary)
                .lineLimit(6).multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(11)
        case .link:
            VStack(spacing: 7) {
                Image(systemName: "link.circle.fill")
                    .font(.system(size: 30)).foregroundStyle(Color.accentColor.gradient)
                Text(item.url?.host ?? item.displayName)
                    .font(.system(size: 9.5, weight: .medium)).foregroundStyle(.secondary)
                    .lineLimit(2).multilineTextAlignment(.center)
            }
            .padding(10)
        }
    }
}

// MARK: - Stack tile (several files dropped together)

private struct ShelfStackTileView: View {
    let group: ShelfGroup
    let onRemove: () -> Void
    let onUngroup: () -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var thumb: NSImage?
    @State private var hovering = false
    private var dark: Bool { scheme == .dark }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                ForEach([2, 1, 0], id: \.self) { depth in card(depth: depth) }
            }
            .frame(width: ShelfMetrics.cardWidth, height: ShelfMetrics.previewHeight)
            .overlay(alignment: .topTrailing) {
                Text("\(group.items.count)")
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color.accentColor))
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    .padding(3)
            }

            Text(group.displayName)
                .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                .lineLimit(2).multilineTextAlignment(.center)
                .frame(width: ShelfMetrics.tile.width, height: ShelfMetrics.nameHeight, alignment: .top)
        }
        .frame(width: ShelfMetrics.tile.width, height: ShelfMetrics.tile.height)
        .scaleEffect(hovering ? 1.05 : 1.0)
        .animation(.easeOut(duration: 0.13), value: hovering)
        .contentShape(Rectangle())
        .overlay(FileDragHandle(items: group.items, onRemove: onRemove, onUngroup: onUngroup, onHoverChange: { hovering = $0 }))
        .help("\(group.items.count) items · drag out all · right-click for options")
        .task(id: group.id) {
            if let u = group.items.first?.url { thumb = await ThumbnailLoader.thumbnail(for: u) }
        }
    }

    @ViewBuilder private func card(depth: Int) -> some View {
        let off = CGFloat(depth) * 4
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(LinearGradient(
                colors: [dark ? Color.white.opacity(0.13) : Color.white,
                         dark ? Color.white.opacity(0.04) : Color(white: 0.965)],
                startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(dark ? Color.white.opacity(0.09) : Color.black.opacity(0.05), lineWidth: 1))
            .overlay { if depth == 0 { topPreview } }
            .frame(width: ShelfMetrics.cardWidth - off, height: ShelfMetrics.previewHeight - off)
            .shadow(color: dark ? .black.opacity(0.30) : .black.opacity(0.12), radius: 5, y: 3)
            .offset(x: off, y: off / 1.5)
    }

    @ViewBuilder private var topPreview: some View {
        if let thumb {
            Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fill)
                .frame(width: ShelfMetrics.cardWidth - 18, height: ShelfMetrics.previewHeight - 18)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else if let u = group.items.first?.url {
            Image(nsImage: NSWorkspace.shared.icon(forFile: u.path))
                .resizable().aspectRatio(contentMode: .fit).padding(18)
        } else {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 28)).foregroundStyle(Color.accentColor)
        }
    }
}

// MARK: - AppKit drag source (drag out + right-click menu + hover)

private struct FileDragHandle: NSViewRepresentable {
    let items: [ShelfItem]
    let onRemove: () -> Void
    let onUngroup: (() -> Void)?
    let onHoverChange: (Bool) -> Void

    func makeNSView(context: Context) -> NSView {
        DragSourceView(items: items, onRemove: onRemove, onUngroup: onUngroup, onHoverChange: onHoverChange)
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? DragSourceView else { return }
        view.items = items
        view.onRemove = onRemove
        view.onUngroup = onUngroup
        view.onHoverChange = onHoverChange
    }
}

/// One tile's handle. `items` is one item for a normal tile or several for a stack; a drag vends them
/// all, and the right-click menu adapts (single-item vs whole-group actions).
private final class DragSourceView: NSView, NSDraggingSource {
    var items: [ShelfItem]
    var onRemove: () -> Void
    var onUngroup: (() -> Void)?
    var onHoverChange: (Bool) -> Void
    private var mouseDownPoint: NSPoint?

    init(items: [ShelfItem], onRemove: @escaping () -> Void, onUngroup: (() -> Void)?, onHoverChange: @escaping (Bool) -> Void) {
        self.items = items
        self.onRemove = onRemove
        self.onUngroup = onUngroup
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
        let dragItems: [NSDraggingItem] = items.compactMap { item in
            guard let writer = writer(for: item) else { return nil }
            let di = NSDraggingItem(pasteboardWriter: writer)
            let icon = icon(for: item); icon.size = NSSize(width: 64, height: 64)
            di.setDraggingFrame(NSRect(x: bounds.midX - 32, y: bounds.midY - 32, width: 64, height: 64), contents: icon)
            return di
        }
        guard !dragItems.isEmpty else { return }
        beginDraggingSession(with: dragItems, event: event, source: self)
    }

    private func writer(for item: ShelfItem) -> NSPasteboardWriting? {
        switch item.kind {
        case .file, .image, .link: return item.url.map { $0 as NSURL }
        case .text: return (item.text ?? "") as NSString
        }
    }
    private func icon(for item: ShelfItem) -> NSImage {
        switch item.kind {
        case .file, .image: if let u = item.url { return NSWorkspace.shared.icon(forFile: u.path) }
        case .link: if let i = NSImage(systemSymbolName: "link", accessibilityDescription: nil) { return i }
        case .text: if let i = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil) { return i }
        }
        return NSImage(systemSymbolName: "doc", accessibilityDescription: nil) ?? NSImage()
    }

    private var fileURLs: [URL] { items.compactMap { ($0.kind == .file || $0.kind == .image) ? $0.url : nil } }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        if items.allSatisfy({ $0.kind == .file || $0.kind == .image }),
           UserDefaults.standard.bool(forKey: "module.shelf.moveOnDrag") {
            return [.move, .copy]
        }
        return .copy
    }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        if operation == .move { onRemove() }   // files were moved away → drop the tile too
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let g = items.count > 1
        let menu = NSMenu()
        if !fileURLs.isEmpty { add(menu, g ? "Quick Look All" : "Quick Look", #selector(quickLookItems)) }
        if g {
            add(menu, "Open All", #selector(openItems))
        } else if let only = items.first, only.kind != .text {
            add(menu, only.kind == .link ? "Open Link" : "Open", #selector(openItems))
        }
        add(menu, g ? "Copy All" : "Copy", #selector(copyItems))
        add(menu, g ? "Share All…" : "Share…", #selector(shareItems))
        if !fileURLs.isEmpty { add(menu, g ? "Reveal All in Finder" : "Reveal in Finder", #selector(revealItems)) }
        if g, onUngroup != nil { add(menu, "Ungroup", #selector(ungroupItems)) }
        menu.addItem(.separator())
        add(menu, g ? "Remove Group" : "Remove from Shelf", #selector(removeItems))
        return menu
    }
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector) {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: "")
        mi.target = self; menu.addItem(mi)
    }

    @objc private func removeItems() { onRemove() }
    @objc private func ungroupItems() { onUngroup?() }
    @objc private func revealItems() { let us = fileURLs; if !us.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(us) } }
    @objc private func openItems() { for it in items { if let u = it.url { NSWorkspace.shared.open(u) } } }
    @objc private func quickLookItems() { let us = fileURLs; if !us.isEmpty { ShelfQuickLook.shared.show(us) } }
    @objc private func shareItems() {
        var objects: [Any] = []
        for it in items {
            switch it.kind {
            case .file, .image, .link: if let u = it.url { objects.append(u) }
            case .text:                objects.append(it.text ?? "")
            }
        }
        guard !objects.isEmpty else { return }
        NSSharingServicePicker(items: objects).show(relativeTo: bounds, of: self, preferredEdge: .minY)
    }
    @objc private func copyItems() {
        let pb = NSPasteboard.general
        pb.clearContents()
        var objects: [NSPasteboardWriting] = []
        for it in items {
            switch it.kind {
            case .file, .image: if let u = it.url { objects.append(u as NSURL) }
            case .link:         if let u = it.url { objects.append(u.absoluteString as NSString) }
            case .text:         objects.append((it.text ?? "") as NSString)
            }
        }
        if !objects.isEmpty { pb.writeObjects(objects) }
    }
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
            Text(module.controller.store.isEmpty ? "empty" : "\(module.controller.store.totalItems) held")
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
                    title: "Move files out instead of copying",
                    subtitle: "When you drag a file off the shelf, move the original to the destination (and drop it from the shelf) instead of leaving a copy behind. Text and links are always copied."
                ) {
                    Toggle("", isOn: Binding(
                        get: { UserDefaults.standard.bool(forKey: "module.shelf.moveOnDrag") },
                        set: { UserDefaults.standard.set($0, forKey: "module.shelf.moveOnDrag") }
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
                    Text(module.controller.store.isEmpty ? "Empty" : "\(module.controller.store.totalItems) item(s)")
                        .foregroundStyle(.secondary)
                }
                Text("Drop files on the shelf, then drag a tile back out to move/copy it. Right-click a tile to remove it or reveal it in Finder. The drawer floats above everything and follows you across Spaces.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
