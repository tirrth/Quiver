import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

/// What a Drop Deck item holds — files, plus dropped text snippets, links, and images.
enum ShelfItemKind: String, Codable { case file, image, text, link }

/// One item held on the shelf — a file, an image, a text snippet, or a link.
struct ShelfItem: Identifiable, Equatable, Codable {
    var id = UUID()
    var kind: ShelfItemKind
    var url: URL?          // .file/.image → file on disk; .link → the web URL
    var text: String?      // .text → the snippet
    var addedAt = Date()

    var displayName: String {
        switch kind {
        case .file, .image: return url?.lastPathComponent ?? "File"
        case .link:         return url.map { $0.host ?? $0.absoluteString } ?? "Link"
        case .text:
            let t = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? "Text" : String(t.prefix(60))
        }
    }

    /// Identity by content so the same file/link/text isn't added twice.
    static func == (lhs: ShelfItem, rhs: ShelfItem) -> Bool {
        lhs.kind == rhs.kind && lhs.url == rhs.url && lhs.text == rhs.text
    }
}

/// Which screen edge the shelf drawer slides out from.
enum ShelfEdge: String, CaseIterable, Identifiable {
    case right, left, top, bottom
    var id: String { rawValue }
    var label: String {
        switch self {
        case .right: return "Right"
        case .left: return "Left"
        case .top: return "Top"
        case .bottom: return "Bottom"
        }
    }
}

/// Shared geometry so the window size (computed in the controller) matches the tile grid
/// (rendered in SwiftUI). The drawer is sized to its contents so it stays compact.
enum ShelfMetrics {
    static let tile = CGSize(width: 108, height: 126)  // grid cell: card + 2-line name
    static let cardWidth: CGFloat = 104                // elevated preview card (inside the cell)
    static let previewHeight: CGFloat = 90             // card height
    static let nameHeight: CGFloat = 28
    static let spacing: CGFloat = 14
    static let padding: CGFloat = 16
    static let headerHeight: CGFloat = 56
    static let footerHeight: CGFloat = 26
    static let emptyBodyHeight: CGFloat = 140
    static let cornerRadius: CGFloat = 22

    static func columns(for edge: ShelfEdge) -> Int {
        switch edge {
        case .left, .right: return 2
        case .top, .bottom: return 4
        }
    }

    static func width(for edge: ShelfEdge) -> CGFloat {
        let c = CGFloat(columns(for: edge))
        return c * tile.width + (c - 1) * spacing + 2 * padding
    }

    static func windowSize(itemCount: Int, edge: ShelfEdge, maxHeight: CGFloat) -> NSSize {
        let w = width(for: edge)
        guard itemCount > 0 else {
            return NSSize(width: w, height: headerHeight + 1 + emptyBodyHeight)
        }
        let cols = columns(for: edge)
        let rows = max(1, Int(ceil(Double(itemCount) / Double(cols))))
        let gridHeight = CGFloat(rows) * tile.height + CGFloat(rows - 1) * spacing + 2 * padding
        // header + divider + grid + divider + footer
        let total = headerHeight + 1 + gridHeight + 1 + footerHeight
        return NSSize(width: w, height: min(total, maxHeight))
    }
}

/// A shelf entry: one or more items added together. A single dropped file is a group of one (shown as
/// a normal tile); several files dropped in one go form a group (shown as one stacked "stack" tile).
struct ShelfGroup: Identifiable, Codable, Equatable {
    var id = UUID()
    var items: [ShelfItem]
    var isStack: Bool { items.count > 1 }
    var displayName: String { isStack ? "\(items.count) items" : (items.first?.displayName ?? "") }
}

/// On-disk home for the shelves: the persisted list plus a folder for pasted/dropped images and
/// text that have no original file on disk.
enum ShelfStorage {
    static let dir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Quiver/Shelf", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()
    private static var stateFile: URL { dir.appendingPathComponent("items.json") }

    static func load() -> [ShelfGroup] {
        guard let data = try? Data(contentsOf: stateFile) else { return [] }
        if let groups = try? JSONDecoder().decode([ShelfGroup].self, from: data) {
            return groups.compactMap { g in
                let items = prune(g.items)
                return items.isEmpty ? nil : ShelfGroup(id: g.id, items: items)
            }
        }
        // Migrate the older single-item list → each item becomes its own tile.
        if let items = try? JSONDecoder().decode([ShelfItem].self, from: data) {
            return prune(items).map { ShelfGroup(items: [$0]) }
        }
        return []
    }

    static func save(_ groups: [ShelfGroup]) {
        if let data = try? JSONEncoder().encode(groups) { try? data.write(to: stateFile) }
    }

    /// Drop file/image items whose file has since moved or been deleted.
    private static func prune(_ items: [ShelfItem]) -> [ShelfItem] {
        items.filter { item in
            switch item.kind {
            case .file, .image: return item.url.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
            case .text, .link:  return true
            }
        }
    }

    /// Persist raw image data (no source file, e.g. a screenshot dropped from another app) and return its URL.
    static func saveImage(_ data: Data, ext: String) -> URL? {
        let url = dir.appendingPathComponent("img-\(UUID().uuidString).\(ext.isEmpty ? "png" : ext)")
        do { try data.write(to: url); return url } catch { return nil }
    }
}

/// Holds the shelf's entries. Each entry is a `ShelfGroup` (one tile): a single item, or several items
/// added in one go that render as a single stack. Persisted across relaunch.
@MainActor
final class ShelfStore: ObservableObject {
    @Published private(set) var groups: [ShelfGroup]

    init() { groups = ShelfStorage.load() }

    var isEmpty: Bool { groups.isEmpty }
    /// Number of tiles (groups) — drives the grid layout / window size.
    var count: Int { groups.count }
    /// Total items across all groups — drives the status text.
    var totalItems: Int { groups.reduce(0) { $0 + $1.items.count } }
    var allItems: [ShelfItem] { groups.flatMap(\.items) }

    // MARK: Add

    /// Add a batch as ONE group (a single drop / paste). 1 item → a normal tile; several → a stack.
    func addItems(_ incoming: [ShelfItem]) {
        let fresh = incoming.filter { item in !allItems.contains(item) }
        guard !fresh.isEmpty else { return }
        groups.append(ShelfGroup(items: fresh)); persist()
    }

    @discardableResult
    func add(urls: [URL]) -> Int {
        let items = urls.filter(\.isFileURL).map { ShelfItem(kind: Self.isImage($0) ? .image : .file, url: $0) }
        let before = totalItems
        addItems(items)
        return totalItems - before
    }

    /// Add plain text — but if it's just a web URL, file it as a link instead.
    func add(text raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https", !trimmed.contains(" ") {
            add(link: url); return
        }
        addItems([ShelfItem(kind: .text, text: trimmed)])
    }

    func add(link: URL) { addItems([ShelfItem(kind: .link, url: link)]) }

    func add(imageData: Data, ext: String) {
        guard let url = ShelfStorage.saveImage(imageData, ext: ext) else { return }
        addItems([ShelfItem(kind: .image, url: url)])
    }

    // MARK: Remove

    func removeGroup(_ id: UUID) { groups.removeAll { $0.id == id }; persist() }

    /// Remove a single item from wherever it lives; a group that empties out is dropped.
    func removeItem(_ item: ShelfItem) {
        for i in groups.indices { groups[i].items.removeAll { $0.id == item.id } }
        groups.removeAll { $0.items.isEmpty }
        persist()
    }

    func clear() { groups.removeAll(); persist() }

    /// Split a stack back into individual tiles.
    func ungroup(_ id: UUID) {
        guard let i = groups.firstIndex(where: { $0.id == id }) else { return }
        let g = groups.remove(at: i)
        groups.insert(contentsOf: g.items.map { ShelfGroup(items: [$0]) }, at: i)
        persist()
    }

    // MARK: Shelf-wide actions

    var fileURLs: [URL] { allItems.compactMap { ($0.kind == .file || $0.kind == .image) ? $0.url : nil } }

    func copyAllToPasteboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        var objects: [NSPasteboardWriting] = []
        for item in allItems {
            switch item.kind {
            case .file, .image, .link: if let u = item.url { objects.append(u as NSURL) }
            case .text:                if let t = item.text { objects.append(t as NSString) }
            }
        }
        if !objects.isEmpty { pb.writeObjects(objects) }
    }

    func compressToZip() {
        let files = fileURLs
        guard !files.isEmpty else { return }
        let dir = ShelfStorage.dir
        Task.detached(priority: .userInitiated) {
            let zipURL = dir.appendingPathComponent("Deck-\(Int(Date().timeIntervalSince1970)).zip")
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            proc.arguments = ["-j", "-q", zipURL.path] + files.map(\.path)   // -j flattens paths
            try? proc.run(); proc.waitUntilExit()
            if FileManager.default.fileExists(atPath: zipURL.path) {
                await MainActor.run { _ = self.add(urls: [zipURL]) }
            }
        }
    }

    private func persist() { ShelfStorage.save(groups) }

    private static func isImage(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) ?? false
    }
}

/// Drag-and-drop deck utility: a floating tray you drop files onto so you can switch windows/Spaces and
/// then drag them back out wherever you want.
@MainActor
final class ShelfModule: UtilityModule {
    let controller = ShelfController()
    let serviceProvider = ShelfServiceProvider()
    private var cancellables = Set<AnyCancellable>()

    init() {
        super.init(
            id: "shelf",
            title: "Drop Deck",
            subtitle: "A floating tray for dragging files: drop them here, switch windows or Spaces, then drag them back out wherever you want.",
            symbolName: "tray.full"
        )
        controller.loadSettings(defaultsKeyPrefix: "module.\(id)")
        serviceProvider.store = controller.store

        // Reflect shelf contents in the menu-bar status.
        controller.store.objectWillChange
            .sink { [weak self] in DispatchQueue.main.async { self?.notifyChange() } }
            .store(in: &cancellables)
    }

    override func start() { controller.start() }
    override func stop() { controller.stop() }

    override var defaultTileSize: TileSize { .wide }
    override var controlCenterTitle: String { "Deck" }
    override var controlCenterStatusSummary: String {
        guard isEnabled else { return "Off" }
        return controller.store.isEmpty ? "Empty" : "\(controller.store.totalItems) held"
    }

    override var statusSummary: String {
        guard isEnabled else { return "Off" }
        if controller.store.isEmpty { return "On · empty · drag files in" }
        let n = controller.store.totalItems
        return n == 1 ? "On · 1 file held" : "On · \(n) files held"
    }

    func openShelf() { controller.openShelf(forceVisible: true) }

    override func makeQuickControls() -> AnyView? {
        AnyView(ShelfQuickControls(module: self))
    }

    override func makeSettingsView() -> AnyView {
        AnyView(ShelfSettingsView(module: self))
    }
}

/// Backs the system-wide "Add to Quiver Drop Deck" Service (right-click → Services in any app). Declared
/// in Info.plist (NSServices → addToShelf) and registered as `NSApp.servicesProvider` at launch.
final class ShelfServiceProvider: NSObject {
    weak var store: ShelfStore?

    @objc func addToShelf(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>?) {
        let store = self.store
        if let urls = pboard.readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty {
            let files = urls.filter(\.isFileURL)
            let links = urls.filter { !$0.isFileURL }
            Task { @MainActor in
                if !files.isEmpty { store?.add(urls: files) }
                links.forEach { store?.add(link: $0) }
            }
        } else if let text = pboard.string(forType: .string) {
            Task { @MainActor in store?.add(text: text) }
        }
    }
}
