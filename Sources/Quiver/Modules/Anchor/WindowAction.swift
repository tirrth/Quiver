import Foundation
import Carbon.HIToolbox

/// One window arrangement Anchor can perform, with its menu metadata and default global shortcut.
enum WindowAction: String, CaseIterable, Identifiable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case maximize, center
    case restore, previousDisplay, nextDisplay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .leftHalf: return "Left Half"
        case .rightHalf: return "Right Half"
        case .topHalf: return "Top Half"
        case .bottomHalf: return "Bottom Half"
        case .topLeft: return "Top Left"
        case .topRight: return "Top Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        case .maximize: return "Maximize"
        case .center: return "Center"
        case .restore: return "Restore"
        case .previousDisplay: return "Previous Display"
        case .nextDisplay: return "Next Display"
        }
    }

    var symbolName: String {
        switch self {
        case .leftHalf: return "rectangle.lefthalf.filled"
        case .rightHalf: return "rectangle.righthalf.filled"
        case .topHalf: return "rectangle.tophalf.filled"
        case .bottomHalf: return "rectangle.bottomhalf.filled"
        case .topLeft: return "rectangle.inset.topleft.filled"
        case .topRight: return "rectangle.inset.topright.filled"
        case .bottomLeft: return "rectangle.inset.bottomleft.filled"
        case .bottomRight: return "rectangle.inset.bottomright.filled"
        case .maximize: return "arrow.up.left.and.arrow.down.right"
        case .center: return "rectangle.center.inset.filled"
        case .restore: return "arrow.uturn.backward"
        case .previousDisplay: return "arrow.left.to.line"
        case .nextDisplay: return "arrow.right.to.line"
        }
    }

    /// Default global shortcut. The tiling actions use Control+Option (Rectangle-style, so they don't
    /// collide with macOS's own Fn-based tiling); the display moves add Command.
    var defaultShortcut: Shortcut {
        let ctrlOpt = UInt32(controlKey | optionKey)
        let ctrlOptCmd = UInt32(controlKey | optionKey | cmdKey)
        switch self {
        case .leftHalf:    return Shortcut(keyCode: UInt32(kVK_LeftArrow), modifiers: ctrlOpt)
        case .rightHalf:   return Shortcut(keyCode: UInt32(kVK_RightArrow), modifiers: ctrlOpt)
        case .topHalf:     return Shortcut(keyCode: UInt32(kVK_UpArrow), modifiers: ctrlOpt)
        case .bottomHalf:  return Shortcut(keyCode: UInt32(kVK_DownArrow), modifiers: ctrlOpt)
        case .topLeft:     return Shortcut(keyCode: UInt32(kVK_ANSI_U), modifiers: ctrlOpt)
        case .topRight:    return Shortcut(keyCode: UInt32(kVK_ANSI_I), modifiers: ctrlOpt)
        case .bottomLeft:  return Shortcut(keyCode: UInt32(kVK_ANSI_J), modifiers: ctrlOpt)
        case .bottomRight: return Shortcut(keyCode: UInt32(kVK_ANSI_K), modifiers: ctrlOpt)
        case .maximize:    return Shortcut(keyCode: UInt32(kVK_Return), modifiers: ctrlOpt)
        case .center:      return Shortcut(keyCode: UInt32(kVK_ANSI_C), modifiers: ctrlOpt)
        case .restore:         return Shortcut(keyCode: UInt32(kVK_Delete), modifiers: ctrlOpt)
        case .previousDisplay: return Shortcut(keyCode: UInt32(kVK_LeftArrow), modifiers: ctrlOptCmd)
        case .nextDisplay:     return Shortcut(keyCode: UInt32(kVK_RightArrow), modifiers: ctrlOptCmd)
        }
    }

    /// Edge halves can be re-triggered to cycle through ½ → ⅔ → ⅓ of the screen.
    var isCyclable: Bool {
        switch self {
        case .leftHalf, .rightHalf, .topHalf, .bottomHalf: return true
        default: return false
        }
    }

    /// Fractions an edge half cycles through on repeated presses.
    static let cycleFractions: [CGFloat] = [0.5, 2.0 / 3.0, 1.0 / 3.0]

    /// Target rectangle inside a screen's visible area (AppKit bottom-left coordinates), with `gap`
    /// kept as a margin against the screen edges and between tiled windows. For the edge halves,
    /// `fraction` selects how much of the screen to take (½/⅔/⅓); ignored by the other actions.
    func frame(in visible: CGRect, gap: CGFloat, fraction: CGFloat = 0.5) -> CGRect {
        let area = visible.insetBy(dx: gap, dy: gap)
        let seam = gap / 2   // half-gap on the shared edge so two tiled windows total one full gap
        switch self {
        case .maximize:
            return area
        case .leftHalf:
            let w = area.width * fraction - seam
            return CGRect(x: area.minX, y: area.minY, width: w, height: area.height)
        case .rightHalf:
            let w = area.width * fraction - seam
            return CGRect(x: area.maxX - w, y: area.minY, width: w, height: area.height)
        case .topHalf:
            let h = area.height * fraction - seam
            return CGRect(x: area.minX, y: area.maxY - h, width: area.width, height: h)
        case .bottomHalf:
            let h = area.height * fraction - seam
            return CGRect(x: area.minX, y: area.minY, width: area.width, height: h)
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            let halfW = (area.width - gap) / 2
            let halfH = (area.height - gap) / 2
            let rightX = area.minX + halfW + gap
            let topY = area.minY + halfH + gap
            switch self {
            case .topLeft:     return CGRect(x: area.minX, y: topY,       width: halfW, height: halfH)
            case .topRight:    return CGRect(x: rightX,    y: topY,       width: halfW, height: halfH)
            case .bottomLeft:  return CGRect(x: area.minX, y: area.minY,  width: halfW, height: halfH)
            default:           return CGRect(x: rightX,    y: area.minY,  width: halfW, height: halfH)
            }
        case .center:
            let w = area.width * 0.65, h = area.height * 0.75
            return CGRect(x: area.midX - w / 2, y: area.midY - h / 2, width: w, height: h)
        case .restore, .previousDisplay, .nextDisplay:
            return area   // handled specially by the engine; never reached through frame()
        }
    }
}
