import SwiftUI

/// Layout value carrying a tile's span in grid cells, set per child via `.tileSpan(_:_:)`.
struct TileSpanKey: LayoutValueKey {
    static let defaultValue: TileCells = TileCells(w: 1, h: 1)
}

struct TileCells: Equatable {
    var w: Int
    var h: Int
}

extension View {
    /// Declare how many grid cells this tile occupies (width × height) for `TileGridLayout`.
    func tileSpan(_ w: Int, _ h: Int) -> some View {
        layoutValue(key: TileSpanKey.self, value: TileCells(w: w, h: h))
    }
}

/// Packs variable-size tiles into a fixed-column grid of square cells, top-to-bottom, first-fit
/// (so later tiles fill gaps left by larger ones — like Control Center). Cells are square and sized
/// to the available width; the grid grows in height to fit.
struct TileGridLayout: Layout {
    var columns: Int = 4
    var spacing: CGFloat = 10

    private func cellSide(forWidth width: CGFloat) -> CGFloat {
        guard columns > 0 else { return 0 }
        return max(1, (width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
    }

    /// First-fit packing → each tile's (col,row) plus the total number of rows used.
    private func pack(_ subviews: Subviews) -> (slots: [(col: Int, row: Int, span: TileCells)], rows: Int) {
        var occupied: [[Bool]] = []
        func ensureRow(_ row: Int) {
            while occupied.count <= row { occupied.append(Array(repeating: false, count: columns)) }
        }
        func fits(col: Int, row: Int, span: TileCells) -> Bool {
            if col + span.w > columns { return false }
            for r in row..<(row + span.h) {
                ensureRow(r)
                for c in col..<(col + span.w) where occupied[r][c] { return false }
            }
            return true
        }
        func occupy(col: Int, row: Int, span: TileCells) {
            for r in row..<(row + span.h) {
                ensureRow(r)
                for c in col..<(col + span.w) { occupied[r][c] = true }
            }
        }

        var slots: [(col: Int, row: Int, span: TileCells)] = []
        for subview in subviews {
            let raw = subview[TileSpanKey.self]
            let span = TileCells(w: min(max(1, raw.w), columns), h: max(1, raw.h))
            var row = 0
            placed: while true {
                ensureRow(row + span.h - 1)
                for col in 0...(columns - span.w) where fits(col: col, row: row, span: span) {
                    occupy(col: col, row: row, span: span)
                    slots.append((col, row, span))
                    break placed
                }
                row += 1
            }
        }
        return (slots, occupied.count)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? (CGFloat(columns) * 64 + spacing * CGFloat(columns - 1))
        let side = cellSide(forWidth: width)
        let rows = pack(subviews).rows
        let height = CGFloat(rows) * side + spacing * CGFloat(max(0, rows - 1))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let side = cellSide(forWidth: bounds.width)
        let slots = pack(subviews).slots
        for (index, subview) in subviews.enumerated() {
            let slot = slots[index]
            let x = bounds.minX + CGFloat(slot.col) * (side + spacing)
            let y = bounds.minY + CGFloat(slot.row) * (side + spacing)
            let w = CGFloat(slot.span.w) * side + spacing * CGFloat(slot.span.w - 1)
            let h = CGFloat(slot.span.h) * side + spacing * CGFloat(slot.span.h - 1)
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: w, height: h))
        }
    }
}
