import SwiftUI

// NOTE: Phase A placeholder. Replaced in Phase C with the bridged AutoRaiseEngine
// (extracted from AutoRaise.mm) plus the Accessibility permission flow.
@MainActor
final class AutoRaiseModule: UtilityModule {
    init() {
        super.init(
            id: "autoraise",
            title: "AutoRaise",
            subtitle: "Raise and focus a window just by hovering it (focus-follows-mouse).",
            symbolName: "macwindow.on.rectangle"
        )
    }

    override func makeSettingsView() -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 8) {
                Text("AutoRaise").font(.headline)
                Text("Coming up next — the focus-follows-mouse engine is being wired into Quiver.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        )
    }
}
