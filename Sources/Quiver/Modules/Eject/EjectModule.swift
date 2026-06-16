import Combine
import SwiftUI

/// Lists external/ejectable drives and ejects them with one click — no need to drag to the Trash.
@MainActor
final class EjectModule: UtilityModule {
    let service = EjectService()
    private var cancellable: AnyCancellable?

    init() {
        super.init(
            id: "eject",
            title: "Eject Drives",
            subtitle: "See your external and removable drives and eject them safely with one click.",
            symbolName: "eject.fill",
            isToggleable: false
        )
        service.onError = { [weak self] message in self?.reportError(message) }
        // Mirror the service's volume list into the module so the menu-bar status (count) stays fresh.
        cancellable = service.$volumes
            .sink { [weak self] _ in DispatchQueue.main.async { self?.notifyChange() } }
    }

    override var statusSummary: String {
        let count = service.volumes.count
        switch count {
        case 0: return "No external drives"
        case 1: return "1 external drive"
        default: return "\(count) external drives"
        }
    }

    override func makeQuickControls() -> AnyView? {
        AnyView(EjectQuickControls(module: self))
    }

    override func makeSettingsView() -> AnyView {
        AnyView(EjectSettingsView(module: self))
    }
}
