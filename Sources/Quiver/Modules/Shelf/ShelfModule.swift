import AppKit
import Combine
import SwiftUI

/// One file held on the shelf.
struct ShelfItem: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    var displayName: String { url.lastPathComponent }
    static func == (lhs: ShelfItem, rhs: ShelfItem) -> Bool { lhs.url == rhs.url }
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
    static let tile = CGSize(width: 96, height: 112)   // preview + name label
    static let previewHeight: CGFloat = 82
    static let spacing: CGFloat = 12
    static let padding: CGFloat = 14
    static let headerHeight: CGFloat = 38
    static let emptyBodyHeight: CGFloat = 122
    static let cornerRadius: CGFloat = 16

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
            return NSSize(width: w, height: headerHeight + emptyBodyHeight)
        }
        let cols = columns(for: edge)
        let rows = max(1, Int(ceil(Double(itemCount) / Double(cols))))
        let gridHeight = CGFloat(rows) * tile.height + CGFloat(rows - 1) * spacing + 2 * padding
        return NSSize(width: w, height: min(headerHeight + gridHeight, maxHeight))
    }
}

/// Holds the shelf's files. Items are kept by reference (the app isn't sandboxed), so dragging one
/// back out vends the original file URL.
@MainActor
final class ShelfStore: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []

    var isEmpty: Bool { items.isEmpty }
    var count: Int { items.count }

    @discardableResult
    func add(urls: [URL]) -> Int {
        var added = 0
        for url in urls where url.isFileURL && !items.contains(where: { $0.url == url }) {
            items.append(ShelfItem(url: url))
            added += 1
        }
        return added
    }

    func remove(_ item: ShelfItem) { items.removeAll { $0.id == item.id } }
    func clear() { items.removeAll() }
}

/// "Drag shelf" utility: a floating tray you drop files onto so you can switch windows/Spaces and
/// then drag them back out wherever you want (like Yoink / Dropover).
@MainActor
final class ShelfModule: UtilityModule {
    let controller = ShelfController()
    private var cancellables = Set<AnyCancellable>()

    init() {
        super.init(
            id: "shelf",
            title: "Shelf",
            subtitle: "A floating tray for dragging files: drop them here, switch windows or Spaces, then drag them back out wherever you want.",
            symbolName: "tray.full"
        )
        controller.loadSettings(defaultsKeyPrefix: "module.\(id)")

        // Reflect shelf contents in the menu-bar status.
        controller.store.objectWillChange
            .sink { [weak self] in DispatchQueue.main.async { self?.notifyChange() } }
            .store(in: &cancellables)
    }

    override func start() { controller.start() }
    override func stop() { controller.stop() }

    override var statusSummary: String {
        guard isEnabled else { return "Off" }
        if controller.store.isEmpty { return "On · empty · drag files in" }
        return controller.store.count == 1 ? "On · 1 file held" : "On · \(controller.store.count) files held"
    }

    func openShelf() { controller.openShelf(forceVisible: true) }

    override func makeQuickControls() -> AnyView? {
        AnyView(ShelfQuickControls(module: self))
    }

    override func makeSettingsView() -> AnyView {
        AnyView(ShelfSettingsView(module: self))
    }
}
