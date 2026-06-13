import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Floating panel content

struct ShelfPanelView: View {
    @ObservedObject var store: ShelfStore
    let onClear: () -> Void
    let onClose: () -> Void

    @State private var targeted = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                if store.items.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 6) {
                        ForEach(store.items) { item in
                            ShelfItemRow(item: item, onRemove: { store.remove(item) })
                        }
                    }
                    .padding(8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            footer
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(targeted ? Color.accentColor : Color.clear, lineWidth: 2)
                .padding(2)
                .allowsHitTesting(false)
        )
        .onDrop(of: [UTType.fileURL], isTargeted: $targeted) { providers in
            handleDrop(providers)
        }
        .frame(minWidth: 220, minHeight: 240)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 30)).foregroundStyle(.secondary)
            Text("Drag files here").font(.callout.weight(.medium))
            Text("Then switch windows or Spaces and drag them back out wherever you want.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 18).padding(.vertical, 34)
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack {
            Text(store.count == 1 ? "1 item" : "\(store.count) items")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            if !store.isEmpty {
                Button("Clear", action: onClear).controlSize(.small)
            }
        }
        .padding(8)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let store = self.store
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                var url: URL?
                if let data = data as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                else if let u = data as? URL { url = u }
                if let url, url.isFileURL {
                    DispatchQueue.main.async { store.add(urls: [url]) }
                }
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
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable().frame(width: 26, height: 26)
            Text(item.displayName)
                .font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 4)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .help("Remove from shelf")
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.08)))
        .contentShape(Rectangle())
        .onDrag { NSItemProvider(object: item.url as NSURL) }
        .help("Drag out to move/copy this file")
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
                    title: "Pop up when I start dragging files",
                    subtitle: "The shelf appears automatically as soon as you begin dragging files. Turn off to open it only from the menu."
                ) {
                    Toggle("", isOn: Binding(
                        get: { module.controller.autoPop },
                        set: { module.controller.setAutoPop($0); module.notifyChange() }
                    )).labelsHidden().toggleStyle(.switch)
                }

                Divider()

                SettingRow(
                    title: "Appears at",
                    subtitle: "Which screen corner the shelf shows in."
                ) {
                    Picker("", selection: Binding(
                        get: { module.controller.corner },
                        set: { module.controller.setCorner($0); module.notifyChange() }
                    )) {
                        ForEach(ShelfCorner.allCases) { corner in
                            Text(corner.label).tag(corner)
                        }
                    }
                    .labelsHidden().frame(width: 150)
                }
            }

            Card(title: "Shelf") {
                HStack {
                    Button { module.openShelf() } label: { Label("Open shelf now", systemImage: "tray.full") }
                    Spacer()
                    Text(module.controller.store.isEmpty ? "Empty" : "\(module.controller.store.count) item(s)")
                        .foregroundStyle(.secondary)
                }
                Text("Drop files on the shelf, navigate to where you want them, then drag them back out. It floats above everything and follows you across Spaces.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
