@preconcurrency import AVFoundation
import AppKit
import Combine
import SwiftUI

/// Owns the camera capture session and the floating mirror panel. The session is started only while
/// the panel is visible and stopped as soon as it closes (so the camera light turns off).
@MainActor
final class MirrorController: NSObject, ObservableObject {
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.tirth.quiver.mirror.session")
    private var panel: NSPanel?
    private var escMonitor: Any?
    private var clickMonitor: Any?
    private var pendingAnchor: NSRect?
    private var prefix = "module.mirror"

    @Published private(set) var mirrored = true
    @Published private(set) var shape: MirrorShape = .rounded
    @Published private(set) var size: MirrorSize = .medium
    @Published private(set) var deviceID: String?
    @Published private(set) var isOpen = false

    var authorization: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .video) }

    // MARK: Settings

    func loadSettings(prefix: String) {
        self.prefix = prefix
        let d = UserDefaults.standard
        mirrored = d.object(forKey: key("mirrored")) as? Bool ?? true
        if let s = d.string(forKey: key("shape")), let v = MirrorShape(rawValue: s) { shape = v }
        if let s = d.string(forKey: key("size")), let v = MirrorSize(rawValue: s) { size = v }
        deviceID = d.string(forKey: key("device"))
    }
    private func key(_ s: String) -> String { "\(prefix).\(s)" }

    func setMirrored(_ value: Bool) { mirrored = value; UserDefaults.standard.set(value, forKey: key("mirrored")) }
    func setShape(_ value: MirrorShape) {
        shape = value
        UserDefaults.standard.set(value.rawValue, forKey: key("shape"))
        if isOpen { sizePanel(animate: true) }
    }
    func setSize(_ value: MirrorSize) {
        size = value
        UserDefaults.standard.set(value.rawValue, forKey: key("size"))
        if isOpen { sizePanel(animate: true) }
    }
    func selectCamera(_ id: String?) {
        deviceID = id
        UserDefaults.standard.set(id, forKey: key("device"))
        if isOpen { configureSession() }
    }

    // MARK: Cameras

    func cameras() -> [AVCaptureDevice] {
        var types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]
        if #available(macOS 14.0, *) {
            types.append(.external)
            types.append(.continuityCamera)
        }
        return AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: .unspecified).devices
    }

    private func selectedDevice() -> AVCaptureDevice? {
        let all = cameras()
        if let id = deviceID, let match = all.first(where: { $0.uniqueID == id }) { return match }
        return AVCaptureDevice.default(for: .video) ?? all.first
    }

    func cycleCamera() {
        let all = cameras()
        guard all.count > 1 else { return }
        let currentID = selectedDevice()?.uniqueID
        let index = all.firstIndex { $0.uniqueID == currentID } ?? 0
        selectCamera(all[(index + 1) % all.count].uniqueID)
    }

    // MARK: Open / close

    func toggle(anchor: NSRect? = nil) { isOpen ? close() : open(anchor: anchor) }

    func open(anchor: NSRect? = nil) {
        pendingAnchor = anchor
        switch authorization {
        case .authorized:
            reallyOpen()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.objectWillChange.send()
                    if granted { self?.reallyOpen() }
                }
            }
        case .denied, .restricted:
            openPrivacySettings()
        @unknown default:
            break
        }
    }

    private func reallyOpen() {
        configureSession()
        startSession()
        showPanel()
        isOpen = true
        // Re-apply mirroring once the connection is live (it forms asynchronously).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.objectWillChange.send() }
    }

    func close() {
        stopSession()
        if let escMonitor { NSEvent.removeMonitor(escMonitor); self.escMonitor = nil }
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor); self.clickMonitor = nil }
        panel?.orderOut(nil)
        isOpen = false
    }

    // MARK: Session

    private func configureSession() {
        let device = selectedDevice()
        sessionQueue.async { [session] in
            session.beginConfiguration()
            session.sessionPreset = .high
            for input in session.inputs { session.removeInput(input) }
            if let device, let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
                session.addInput(input)
            }
            session.commitConfiguration()
        }
    }
    private func startSession() { sessionQueue.async { [session] in if !session.isRunning { session.startRunning() } } }
    private func stopSession() { sessionQueue.async { [session] in if session.isRunning { session.stopRunning() } } }

    // MARK: Panel

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 255),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered, defer: false
        )
        p.minSize = NSSize(width: 160, height: 120)
        p.isMovable = true
        p.isMovableByWindowBackground = true
        p.level = .floating
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        p.isReleasedWhenClosed = false
        let host = NSHostingController(rootView: MirrorPanelView(controller: self))
        host.view.wantsLayer = true
        host.view.layer?.backgroundColor = NSColor.clear.cgColor
        p.contentViewController = host
        panel = p
        return p
    }

    private func showPanel() {
        let p = ensurePanel()
        let wasVisible = p.isVisible
        sizePanel(animate: false)
        if !wasVisible {
            let s = size.dimensions(circle: shape == .circle)
            if let anchor = pendingAnchor {
                // Open just below the menu-bar icon, clamped to the screen.
                let screen = NSScreen.screens.first { NSMouseInRect(NSPoint(x: anchor.midX, y: anchor.midY), $0.frame, false) } ?? NSScreen.main
                var x = anchor.midX - s.width / 2
                if let vf = screen?.visibleFrame {
                    x = min(max(x, vf.minX + 8), vf.maxX - s.width - 8)
                }
                p.setFrameTopLeftPoint(NSPoint(x: x, y: anchor.minY - 4))
            } else if let screen = screenUnderMouse() {
                p.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - s.width / 2,
                                         y: screen.visibleFrame.midY - s.height / 2))
            }
        }
        p.orderFrontRegardless()
        installEscMonitor()
        installClickMonitor()
    }

    private func sizePanel(animate: Bool) {
        guard let p = panel else { return }
        let s = size.dimensions(circle: shape == .circle)
        var frame = p.frame
        // keep the center fixed while resizing
        frame.origin.x += (frame.width - s.width) / 2
        frame.origin.y += (frame.height - s.height) / 2
        frame.size = s
        p.contentAspectRatio = s   // keep the shape's ratio while the user drags to resize
        p.setFrame(frame, display: true, animate: animate)
    }

    private func installEscMonitor() {
        guard escMonitor == nil else { return }
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.close(); return nil }   // Esc
            return event
        }
    }

    private func installClickMonitor() {
        guard clickMonitor == nil else { return }
        // A click outside the panel (another app or the desktop) dismisses it. Global monitors don't
        // fire for our own clicks, so interacting with — or resizing — the panel keeps it open.
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.close()
        }
    }

    private func screenUnderMouse() -> NSScreen? {
        let loc = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(loc, $0.frame, false) } ?? NSScreen.main
    }

    private func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }
}
