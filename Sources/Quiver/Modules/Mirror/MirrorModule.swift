import AVFoundation
import SwiftUI
import Combine

enum MirrorShape: String, CaseIterable, Identifiable {
    case rounded, circle
    var id: String { rawValue }
    var label: String { self == .rounded ? "Rounded" : "Circle" }
}

enum MirrorSize: String, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }
    var label: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }
    /// 4:3 for rounded, square for circle.
    func dimensions(circle: Bool) -> CGSize {
        if circle {
            let d: CGFloat = self == .small ? 190 : (self == .medium ? 250 : 320)
            return CGSize(width: d, height: d)
        }
        let w: CGFloat = self == .small ? 260 : (self == .medium ? 340 : 440)
        return CGSize(width: w, height: (w * 3 / 4).rounded())
    }
}

/// Hand-Mirror–style utility: pop up a quick floating webcam mirror to check yourself before a
/// meeting. A "tool" module (you open it; there's no background engine). The camera only runs while
/// the mirror is on screen.
@MainActor
final class MirrorModule: UtilityModule {
    let controller = MirrorController()
    private var cancellables = Set<AnyCancellable>()

    init() {
        super.init(
            id: "mirror",
            title: "Mirror",
            subtitle: "Pop up a quick webcam mirror so you can check yourself before a meeting. The camera runs only while the mirror is open.",
            symbolName: "person.crop.square",
            isToggleable: false
        )
        controller.loadSettings(prefix: "module.\(id)")
        controller.objectWillChange
            .sink { [weak self] in DispatchQueue.main.async { self?.notifyChange() } }
            .store(in: &cancellables)
    }

    func openMirror() { controller.toggle() }

    override var statusSummary: String {
        switch controller.authorization {
        case .denied, .restricted: return "Camera access needed"
        default: return controller.isOpen ? "Mirror is open" : "Check your camera"
        }
    }

    override var permission: PermissionState {
        switch controller.authorization {
        case .authorized, .notDetermined: return .ok      // notDetermined → we prompt on open
        case .denied: return .needed(reason: "Camera access lets Mirror show your webcam.", actionTitle: "Open Settings")
        case .restricted: return .unavailable(reason: "Camera access is restricted on this Mac.")
        @unknown default: return .ok
        }
    }

    override func requestPermission() { controller.open() }

    override func makeQuickControls() -> AnyView? { AnyView(MirrorQuickControls(module: self)) }
    override func makeSettingsView() -> AnyView { AnyView(MirrorSettingsView(module: self)) }
}
