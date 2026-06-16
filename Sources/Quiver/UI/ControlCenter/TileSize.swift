import Foundation

/// The size a module's Control-Center tile occupies in the packing grid, in grid cells.
enum TileSize: String, CaseIterable, Codable {
    case small   // 1×1
    case wide    // 2×1
    case large   // 2×2

    /// Width/height of the tile measured in grid cells.
    var cells: (w: Int, h: Int) {
        switch self {
        case .small: return (1, 1)
        case .wide:  return (2, 1)
        case .large: return (2, 2)
        }
    }

    /// Cycle order used by the in-hub size button: small → wide → large → small.
    var next: TileSize {
        switch self {
        case .small: return .wide
        case .wide:  return .large
        case .large: return .small
        }
    }

    var label: String {
        switch self {
        case .small: return "Small"
        case .wide:  return "Wide"
        case .large: return "Large"
        }
    }
}
