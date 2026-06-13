import SwiftUI

// NOTE: Phase A placeholder. Replaced in Phase B with the ported HostsMachine engine
// (HostsFileService + privileged helper + editor UI).
@MainActor
final class HostsModule: UtilityModule {
    init() {
        super.init(
            id: "hosts",
            title: "Hosts",
            subtitle: "View, edit, enable/disable, and add entries in /etc/hosts.",
            symbolName: "network"
        )
    }

    override func makeSettingsView() -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 8) {
                Text("Hosts editor").font(.headline)
                Text("Coming up next — the /etc/hosts editor is being wired into Quiver.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        )
    }
}
