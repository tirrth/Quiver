import SwiftUI

/// A reusable menu-bar icon picker: browse the SF Symbol catalog by category (or search it), pick a
/// glyph (or keep the built-in default), and fine-tune its size and vertical position with sliders —
/// all with a live preview. Used for each utility's icon and for the Quiver app's own menu-bar icon.
struct IconPicker: View {
    /// The currently chosen symbol; `nil` means "use the default".
    let selectedSymbol: String?
    /// The built-in glyph this picker defaults to; `nil` means the Quiver gem (drawn via `GemMark`).
    let defaultSymbolName: String?
    /// `scale` is the Size slider's multiplier (1 = 100%); `baselineScale` is the icon's designed size
    /// that 100% maps to, so the preview reflects the real rendered size (baseline × multiplier).
    let scale: CGFloat
    var baselineScale: CGFloat = 1
    let yOffset: CGFloat
    /// Whether this icon has been changed from its default (drives the Reset button).
    var isModified: Bool = false

    let onPick: (String?) -> Void        // nil = revert to the default glyph
    let onScale: (CGFloat) -> Void
    let onYOffset: (CGFloat) -> Void
    let onReset: () -> Void

    @State private var query = ""

    /// Validate every catalog symbol once (skip any missing on this macOS), de-duplicated across
    /// categories, order kept. Empty categories are dropped.
    private static let validCategories: [SFSymbolCatalog.Category] = {
        var seen = Set<String>()
        return SFSymbolCatalog.categories.compactMap { category in
            let valid = category.symbols.filter { name in
                NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil && seen.insert(name).inserted
            }
            return valid.isEmpty ? nil : SFSymbolCatalog.Category(name: category.name, symbols: valid)
        }
    }()
    private static let validNames: [String] = validCategories.flatMap { $0.symbols }

    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }
    private var results: [String] { Self.validNames.filter { $0.localizedCaseInsensitiveContains(query) } }

    private let columns = [GridItem(.adaptive(minimum: 34), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Live preview + current selection + reset
            HStack(spacing: 12) {
                previewSwatch
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedSymbol ?? (defaultSymbolName ?? "Quiver gem"))
                        .font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    Text(selectedSymbol == nil ? "Default icon" : "Custom icon")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Reset", action: onReset)
                    .controlSize(.small)
                    .disabled(!isModified)
            }

            // Size + vertical nudge
            HStack(spacing: 16) {
                sliderRow("Size", value: scale, range: 0.7...1.3, set: onScale,
                          label: "\(Int((scale * 100).rounded()))%")
                sliderRow("Nudge", value: yOffset, range: -4...4, set: onYOffset,
                          label: String(format: "%.1f", yOffset))
            }

            // Search + browse-by-category grid
            TextField("Search \(Self.validNames.count) icons…", text: $query)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                if isSearching {
                    if results.isEmpty {
                        Text("No icons match “\(query)”")
                            .font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 24)
                    } else {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(results, id: \.self) { cell($0) }
                        }
                        .padding(8)
                    }
                } else {
                    LazyVStack(alignment: .leading, spacing: 6, pinnedViews: [.sectionHeaders]) {
                        ForEach(Self.validCategories) { category in
                            Section {
                                LazyVGrid(columns: columns, spacing: 8) {
                                    ForEach(category.symbols, id: \.self) { cell($0) }
                                }
                                .padding(.horizontal, 8)
                                .padding(.bottom, 8)
                            } header: {
                                sectionHeader(category.name)
                            }
                        }
                    }
                }
            }
            .frame(height: 230)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold)).foregroundStyle(.secondary).tracking(0.5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(.regularMaterial)
    }

    private var previewSwatch: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color(white: 0.16))
            Group {
                let renderScale = baselineScale * scale   // the real rendered size
                if let symbol = selectedSymbol ?? defaultSymbolName {
                    Image(systemName: symbol)
                        .font(.system(size: 14 * renderScale, weight: .regular))
                        .foregroundStyle(.white)
                        .offset(y: yOffset)
                } else {
                    GemMark(size: 16 * renderScale).offset(y: yOffset)
                }
            }
        }
        .frame(width: 30, height: 30)
    }

    private func sliderRow(_ title: String, value: CGFloat, range: ClosedRange<CGFloat>,
                           set: @escaping (CGFloat) -> Void, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(label).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { Double(value) }, set: { set(CGFloat($0)) }),
                   in: Double(range.lowerBound)...Double(range.upperBound))
        }
    }

    private func cell(_ name: String) -> some View {
        Button { onPick(name) } label: {
            Image(systemName: name)
                .font(.system(size: 15))
                .frame(width: 34, height: 30)
                .background(cellBackground(isSelected: selectedSymbol == name))
        }
        .buttonStyle(.plain)
        .help(name)
    }

    private func cellBackground(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
    }
}
