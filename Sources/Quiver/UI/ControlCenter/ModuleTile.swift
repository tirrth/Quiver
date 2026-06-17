import SwiftUI

/// The visual face of a Control-Center tile (no tap handling). Matches macOS Control Center: frosted
/// glass that samples the desktop, with the glyph in a circle — ON fills that circle solid white with
/// an accent glyph; OFF is gray/translucent with a normal glyph. 1×1 = a circle; 2×1 / 2×2 = squircles.
struct ModuleTileFace: View {
    @ObservedObject var module: UtilityModule
    let size: TileSize
    var interactive: Bool = true

    private var isToggle: Bool { module.isToggleable }
    private var isOn: Bool { isToggle && module.isEnabled }
    private var dimmed: Bool { module.permission.unavailableReason != nil }
    private var needsAttention: Bool { module.permission.needed != nil && (isToggle ? module.isEnabled : true) }

    var body: some View {
        Group {
            switch size {
            case .small: small
            case .wide:  wide
            case .large: large
            }
        }
        .opacity(dimmed ? 0.5 : 1)
    }

    private func glyphImage(_ pointSize: CGFloat) -> some View {
        Image(systemName: module.effectiveSymbolName)
            .font(.system(size: pointSize * module.effectiveSymbolScale, weight: .medium))
            .foregroundStyle(isOn ? Color.accentColor : Color.primary)
            .offset(y: module.effectiveSymbolYOffset)
    }

    @ViewBuilder private var attentionBadge: some View {
        if needsAttention {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9)).foregroundStyle(.orange)
        }
    }

    /// Inner icon circle for wide/large tiles: solid white (on) or a gray translucent fill (off).
    private func innerCircle(_ diameter: CGFloat) -> some View {
        ZStack {
            Circle().fill(isOn ? Color.white : Color.primary.opacity(0.16))
            glyphImage(diameter * 0.50)
        }
        .frame(width: diameter, height: diameter)
        .overlay(alignment: .topTrailing) { attentionBadge.offset(x: 2, y: -2) }
    }

    // MARK: Sizes

    /// 1×1 — the whole tile is a circle: solid white when on, frosted glass when off.
    private var small: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height)
            glyphImage(d * 0.40)   // measured against real CC: 1×1 glyph ≈ 0.50 of its circle (~33pt in a 65pt tile)
                .frame(width: geo.size.width, height: geo.size.height)
                .shadow(color: .black.opacity(0.28), radius: 1.5, y: 0.5)   // legibility on light glass
                .background {
                    if isOn {
                        Circle()
                            .fill(.white)
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.45), lineWidth: 1))
                    } else {
                        Color.clear.ccGlassCapsule()
                    }
                }
                .overlay(alignment: .topTrailing) { attentionBadge.offset(x: -d * 0.16, y: d * 0.16) }
        }
    }

    /// 2×1 — frosted glass squircle: icon circle on the left, name + status to the right.
    private var wide: some View {
        HStack(spacing: 12) {
            innerCircle(42)   // measured against real CC: the wide-control icon circle is ~44pt (in a ~63pt tile)
            VStack(alignment: .leading, spacing: 1) {
                Text(module.controlCenterTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                let status = module.controlCenterStatusSummary
                if !status.isEmpty {
                    Text(status)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.74)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .shadow(color: .black.opacity(0.28), radius: 1.5, y: 0.5)   // legibility on light glass
        .ccGlassCapsule()
    }

    /// 2×2 — frosted glass squircle: icon circle, name, then embedded controls (or status).
    private var large: some View {
        VStack(alignment: .leading, spacing: 8) {
            innerCircle(46)
            Text(module.controlCenterTitle).font(.system(size: 16, weight: .semibold)).foregroundStyle(.primary).lineLimit(1)
            if let controls = module.makeQuickControls() {
                controls.allowsHitTesting(interactive)
            } else {
                let status = module.controlCenterStatusSummary
                if !status.isEmpty {
                    Text(status).font(.system(size: 12)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .shadow(color: .black.opacity(0.28), radius: 1.5, y: 0.5)   // legibility on light glass
        .ccGlassRect(28)
    }
}

/// An interactive hub tile: tap toggles a switch-module or opens a tool, like a Control Center control.
struct ModuleTile: View {
    @ObservedObject var module: UtilityModule
    let size: TileSize
    let onOpenModule: (String) -> Void

    private var isToggle: Bool { module.isToggleable }
    private var isOn: Bool { isToggle && module.isEnabled }
    private var disabled: Bool { module.permission.unavailableReason != nil }

    var body: some View {
        Button(action: primaryAction) {
            ModuleTileFace(module: module, size: size)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(module.title + (module.statusSummary.isEmpty ? "" : " · \(module.statusSummary)"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(module.title)
        .accessibilityValue(isToggle ? (isOn ? "On" : "Off") : module.statusSummary)
        .accessibilityAddTraits(.isButton)
    }

    private func primaryAction() {
        if isToggle { module.setEnabled(!module.isEnabled) } else { onOpenModule(module.id) }
    }
}
