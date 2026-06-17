import SwiftUI
import Combine

/// The Hosts utility: view, edit, enable/disable, add, and remove entries in /etc/hosts. This is a
/// "tool" module (no background engine), so it's always available rather than toggled on/off.
@MainActor
final class HostsModule: UtilityModule {
    let viewModel = HostsViewModel()

    @Published private(set) var passwordlessEnabled: Bool
    @Published private(set) var isUpdatingPrivilegedAccess = false

    private var cancellables = Set<AnyCancellable>()

    init() {
        passwordlessEnabled = PasswordlessHostsWriter.isInstalled
        super.init(
            id: "hosts",
            title: "Reroute It",
            subtitle: "View, edit, enable/disable, add, and remove entries in /etc/hosts.",
            symbolName: "arrow.triangle.branch",
            isToggleable: false
        )

        viewModel.errorHandler = { [weak self] message in self?.reportError(message) }
        // Mirror view-model changes into the module so the menu-bar status (counts) stays fresh.
        viewModel.objectWillChange
            .sink { [weak self] in
                DispatchQueue.main.async { self?.notifyChange() }
            }
            .store(in: &cancellables)

        viewModel.load()
    }

    func refresh() {
        viewModel.load()
        refreshPasswordless()
    }

    func refreshPasswordless() {
        let installed = PasswordlessHostsWriter.isInstalled
        if installed != passwordlessEnabled {
            passwordlessEnabled = installed
            notifyChange()
        }
    }

    override var defaultTileSize: TileSize { .wide }

    /// Install or remove the root-owned passwordless helper (one admin prompt).
    func setPasswordless(_ enabled: Bool) {
        let previous = passwordlessEnabled
        isUpdatingPrivilegedAccess = true
        notifyChange()
        defer {
            isUpdatingPrivilegedAccess = false
            notifyChange()
        }
        do {
            if enabled {
                try PasswordlessHostsWriter.installFromBundle()
            } else {
                try PasswordlessHostsWriter.uninstall()
            }
            let actual = PasswordlessHostsWriter.isInstalled
            guard actual == enabled else {
                throw HostsError.adminCommandFailed("Quiver could not verify the privileged helper installation.")
            }
            passwordlessEnabled = actual
        } catch {
            passwordlessEnabled = previous
            reportError(error.localizedDescription)
        }
    }

    override var statusSummary: String {
        "\(viewModel.activeCount) on · \(viewModel.disabledCount) off"
    }

    override var controlCenterTitle: String { "Hosts" }
    override var controlCenterStatusSummary: String {
        "\(viewModel.activeCount) on"
    }

    override func makeQuickControls() -> AnyView? {
        AnyView(HostsQuickControls(module: self))
    }

    override func makeSettingsView() -> AnyView {
        AnyView(HostsSettingsView(module: self))
    }
}
