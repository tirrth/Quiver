import SwiftUI
import AVFoundation
import AppKit

// MARK: - Camera preview (AVCaptureVideoPreviewLayer hosted in an NSView)

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    let mirrored: Bool

    func makeNSView(context: Context) -> PreviewNSView { PreviewNSView(session: session, mirrored: mirrored) }
    func updateNSView(_ nsView: PreviewNSView, context: Context) { nsView.setMirrored(mirrored) }
}

final class PreviewNSView: NSView {
    private let previewLayer: AVCaptureVideoPreviewLayer
    private var desiredMirror: Bool

    init(session: AVCaptureSession, mirrored: Bool) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        desiredMirror = mirrored
        super.init(frame: .zero)
        wantsLayer = true
        let host = CALayer()
        host.addSublayer(previewLayer)
        layer = host
        applyMirror()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
        applyMirror()
    }

    func setMirrored(_ value: Bool) { desiredMirror = value; applyMirror() }

    private func applyMirror() {
        guard let connection = previewLayer.connection, connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = desiredMirror
    }
}

// MARK: - Floating mirror panel

struct MirrorPanelView: View {
    @ObservedObject var controller: MirrorController
    @State private var hovering = false

    private var circle: Bool { controller.shape == .circle }
    private var shape: AnyShape {
        circle ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    var body: some View {
        ZStack {
            CameraPreview(session: controller.session, mirrored: controller.mirrored)
                .clipShape(shape)

            VStack {
                Spacer()
                if hovering {
                    HStack(spacing: 12) {
                        control("arrow.left.arrow.right", "Flip") { controller.setMirrored(!controller.mirrored) }
                        if controller.cameras().count > 1 {
                            control("arrow.triangle.2.circlepath", "Switch camera") { controller.cycleCamera() }
                        }
                        control("xmark", "Close") { controller.close() }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Color.black.opacity(0.5), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
                    .padding(.bottom, circle ? 36 : 12)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(shape.stroke(Color.white.opacity(0.18), lineWidth: 1.5))
        .contentShape(shape)
        .onHover { value in withAnimation(.easeOut(duration: 0.15)) { hovering = value } }
    }

    private func control(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white).frame(width: 24, height: 24)
        }
        .buttonStyle(.plain).help(help)
    }
}

// MARK: - Popover quick controls

struct MirrorQuickControls: View {
    @ObservedObject var module: MirrorModule

    var body: some View {
        Button { module.openMirror() } label: {
            Label(module.controller.isOpen ? "Hide Glance Me" : "Open Glance Me", systemImage: "camera.fill")
        }
        .controlSize(.small)
    }
}

// MARK: - Settings pane

struct MirrorSettingsView: View {
    @ObservedObject var module: MirrorModule
    @ObservedObject var controller: MirrorController

    init(module: MirrorModule) {
        _module = ObservedObject(wrappedValue: module)
        _controller = ObservedObject(wrappedValue: module.controller)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Button { module.openMirror() } label: {
                Label(controller.isOpen ? "Hide Glance Me" : "Open Glance Me", systemImage: "camera.fill")
            }
            .controlSize(.large).buttonStyle(.borderedProminent)

            Card(title: "Appearance") {
                SettingRow(
                    title: "Flip image",
                    subtitle: "Flip horizontally so the image is not reversed."
                ) {
                    Toggle("", isOn: Binding(get: { controller.mirrored }, set: { controller.setMirrored($0) }))
                        .labelsHidden().toggleStyle(.switch)
                }

                Divider()

                SettingRow(title: "Shape", subtitle: nil) {
                    Picker("", selection: Binding(get: { controller.shape }, set: { controller.setShape($0) })) {
                        ForEach(MirrorShape.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.segmented).frame(width: 170)
                }

                Divider()

                SettingRow(title: "Size", subtitle: nil) {
                    Picker("", selection: Binding(get: { controller.size }, set: { controller.setSize($0) })) {
                        ForEach(MirrorSize.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.segmented).frame(width: 200)
                }
            }

            let cameras = controller.cameras()
            if cameras.count > 1 {
                Card(title: "Camera") {
                    Picker("", selection: Binding(
                        get: { controller.deviceID ?? cameras.first?.uniqueID ?? "" },
                        set: { controller.selectCamera($0) }
                    )) {
                        ForEach(cameras, id: \.uniqueID) { camera in
                            Text(camera.localizedName).tag(camera.uniqueID)
                        }
                    }
                    .labelsHidden()
                }
            }

            if controller.authorization == .denied {
                Text("Camera access is off — enable Quiver under System Settings → Privacy & Security → Camera.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
