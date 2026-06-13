import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Drawer content (hosted in the borderless edge window)

struct ShelfDrawerContent: View {
    @ObservedObject var store: ShelfStore
    let onClear: () -> Void
    let onClose: () -> Void

    @State private var targeted = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(targeted ? Color.accentColor : Color.white.opacity(0.12),
                              lineWidth: targeted ? 2 : 1)
        )
        .onDrop(of: [UTType.fileURL], isTargeted: $targeted) { providers in handleDrop(providers) }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "tray.full").font(.caption).foregroundStyle(.secondary)
            Text("Shelf").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Spacer()
            if !store.isEmpty {
                Button("Clear", action: onClear)
                    .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
            }
            Button(action: onClose) { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Hide shelf")
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if store.items.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "tray.and.arrow.down").font(.system(size: 28)).foregroundStyle(.secondary)
                Text("Drag files here").font(.callout.weight(.medium))
                Text("Then switch windows or Spaces and drag them back out.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(20).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(store.items) { item in
                        ShelfItemRow(item: item, onRemove: { store.remove(item) })
                    }
                }
                .padding(8)
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

private struct ShelfItemRow: View {
    let item: ShelfItem
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                    .resizable().frame(width: 26, height: 26)
                Text(item.displayName)
                    .font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            // Native AppKit drag source overlaid on the icon+name area — dragging here starts a real
            // file drag-and-drop session (can't move the window). The remove button stays clickable.
            .overlay(FileDragHandle(url: item.url))

            Button(action: onRemove) { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Remove from shelf")
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.08)))
    }
}

// MARK: - AppKit drag source (drag a file out of the shelf)

private struct FileDragHandle: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> NSView { DragSourceView(url: url) }
    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? DragSourceView)?.url = url
    }
}

private final class DragSourceView: NSView, NSDraggingSource {
    var url: URL
    private var mouseDownPoint: NSPoint?

    init(url: URL) {
        self.url = url
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint else { return }
        let p = event.locationInWindow
        guard hypot(p.x - start.x, p.y - start.y) >= 4 else { return }   // small threshold
        mouseDownPoint = nil

        let dragItem = NSDraggingItem(pasteboardWriter: url as NSURL)
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 40, height: 40)
        dragItem.setDraggingFrame(NSRect(x: bounds.midX - 20, y: bounds.midY - 20, width: 40, height: 40), contents: icon)
        beginDraggingSession(with: [dragItem], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownPoint = nil
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy   // copy the file out (non-destructive)
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
                Text("Drop files on the shelf, navigate to where you want them, then drag a file back out. The drawer floats above everything and follows you across Spaces.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
