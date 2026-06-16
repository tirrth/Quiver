import SwiftUI

/// Full settings pane for the Metal HUD toggle.
struct MetalHUDSettingsView: View {
    @ObservedObject var module: MetalHUDModule

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Card(title: "About the Metal HUD") {
                Text("Apple's Metal Performance HUD overlays frame rate, GPU, and memory stats on any Metal app or game — handy for checking game performance.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                Label("Turn it on, then launch (or relaunch) an app to see the HUD. Apps that are already running keep their current state.",
                      systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if module.isEnabled {
                Label("On — newly launched apps will show the HUD", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green).font(.callout)
            }
        }
    }
}
