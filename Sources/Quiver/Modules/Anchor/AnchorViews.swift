import SwiftUI
import Carbon.HIToolbox

/// Anchor's settings pane: click-to-arrange buttons, a gap picker, and an editable shortcut list.
struct AnchorSettingsView: View {
    @ObservedObject var module: AnchorModule
    @StateObject private var recorder = KeyRecorder()
    @State private var conflict: String?

    private let halves: [WindowAction] = [.leftHalf, .rightHalf, .topHalf, .bottomHalf]
    private let quarters: [WindowAction] = [.topLeft, .topRight, .bottomLeft, .bottomRight]
    private let whole: [WindowAction] = [.maximize, .fullScreen, .center, .restore]
    private let displays: [WindowAction] = [.previousDisplay, .nextDisplay]

    private var canArrange: Bool { module.permission.isOK }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            arrangeCard
            dragCard
            gapCard
            shortcutsCard
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            recorder.onCapture = { action, shortcut in
                if let shortcut {
                    if let other = module.setShortcut(action, shortcut) {
                        conflict = "\(shortcut.display) is already used by \(other.title)."
                    } else {
                        conflict = nil
                    }
                } else {
                    module.clearShortcut(action)
                    conflict = nil
                }
            }
        }
        .onDisappear { recorder.stop() }
    }

    private var arrangeCard: some View {
        Card(title: "Arrange the front window") {
            Text("Snaps the window of the app you were last using. The shortcuts below do the same from anywhere.")
                .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            buttonRow(halves)
            buttonRow(quarters)
            buttonRow(whole, padToFour: true)
            buttonRow(displays, padToFour: true)
        }
        .disabled(!canArrange)
        .opacity(canArrange ? 1 : 0.5)
    }

    private var dragCard: some View {
        Card(title: "Drag to snap") {
            SettingRow(
                title: "Snap by dragging to screen edges",
                subtitle: "Drag a window to an edge or corner; a preview shows the target size, and it snaps when you let go."
            ) {
                Toggle("", isOn: Binding(get: { module.dragSnapEnabled }, set: { module.setDragSnap($0) }))
                    .labelsHidden().toggleStyle(.switch)
            }
        }
    }

    private var gapCard: some View {
        Card(title: "Gap") {
            SettingRow(
                title: "Spacing around snapped windows",
                subtitle: "A margin between windows and the screen edges."
            ) {
                Picker("", selection: Binding(get: { module.gap }, set: { module.setGap($0) })) {
                    ForEach(AnchorModule.gapChoices, id: \.self) { g in
                        Text(g == 0 ? "None" : "\(g) px").tag(g)
                    }
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
            }
        }
    }

    private var shortcutsCard: some View {
        Card(title: "Keyboard shortcuts") {
            Text("Click a shortcut to change it. Press a new combo, Esc to cancel, ⌫ to clear. Repeat a half to cycle ½ → ⅔ → ⅓.")
                .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            if let conflict {
                Label(conflict, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(Array(WindowAction.allCases.enumerated()), id: \.element.id) { index, action in
                shortcutRow(action)
                if index < WindowAction.allCases.count - 1 { Divider() }
            }
            HStack {
                Spacer()
                Button("Reset all to defaults") {
                    module.resetAllShortcuts(); recorder.stop(); conflict = nil
                }
                .controlSize(.small)
            }
        }
    }

    private func shortcutRow(_ action: WindowAction) -> some View {
        let recording = recorder.recording == action
        return HStack(spacing: 10) {
            Image(systemName: action.symbolName).frame(width: 22).foregroundStyle(.secondary)
            Text(action.title).font(.system(size: 13))
            Spacer()
            if module.isOverridden(action) && !recording {
                Button { module.resetShortcut(action); conflict = nil } label: {
                    Image(systemName: "arrow.uturn.backward").font(.system(size: 10))
                }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Reset to default")
            }
            Button { conflict = nil; recorder.start(action) } label: {
                Text(recording ? "Press keys…" : (module.effectiveShortcut(for: action)?.display ?? "Unbound"))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(recording ? Color.accentColor : .secondary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .frame(minWidth: 60)
                    .background(RoundedRectangle(cornerRadius: 6).fill((recording ? Color.accentColor : Color.secondary).opacity(0.15)))
            }
            .buttonStyle(.plain)
        }
    }

    private func buttonRow(_ actions: [WindowAction], padToFour: Bool = false) -> some View {
        HStack(spacing: 8) {
            ForEach(actions) { action in arrangeButton(action) }
            if padToFour {
                ForEach(0..<(4 - actions.count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity, minHeight: 1) }
            }
        }
    }

    private func arrangeButton(_ action: WindowAction) -> some View {
        Button { module.perform(action) } label: {
            VStack(spacing: 4) {
                Image(systemName: action.symbolName).font(.system(size: 16))
                Text(action.title).font(.system(size: 10)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 46)
        }
        .buttonStyle(.bordered)
        .help(action.title + (module.effectiveShortcut(for: action).map { "  " + $0.display } ?? ""))
    }
}

/// Captures the next key combo (while the settings window is key) to rebind an action's shortcut.
@MainActor
final class KeyRecorder: ObservableObject {
    @Published var recording: WindowAction?
    private var monitor: Any?
    /// Called with the captured shortcut, or `nil` to clear (unbind) the action.
    var onCapture: ((WindowAction, Shortcut?) -> Void)?

    func start(_ action: WindowAction) {
        stop()
        recording = action
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return nil   // swallow the key while recording
        }
    }

    private func handle(_ event: NSEvent) {
        guard let action = recording else { return }
        let key = Int(event.keyCode)
        let mods = Shortcut.carbonModifiers(from: event.modifierFlags)
        if mods == 0 {
            if key == kVK_Escape { stop(); return }                         // cancel
            if key == kVK_Delete || key == kVK_ForwardDelete {              // clear (unbind)
                onCapture?(action, nil); stop(); return
            }
            return                                                          // bare key — keep waiting
        }
        guard Shortcut.hasRequiredModifier(mods) else { return }            // shift-only — keep waiting
        onCapture?(action, Shortcut(keyCode: UInt32(key), modifiers: mods))
        stop()
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = nil
    }
}
