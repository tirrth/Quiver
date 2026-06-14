import Carbon.HIToolbox
import AppKit

/// Registers global keyboard shortcuts via Carbon and routes each press to a callback. Carbon
/// hotkeys are process-global, fire regardless of which app is frontmost, and need no extra
/// entitlement. One instance owns a set of hotkeys; `unregisterAll()` tears them down.
final class HotKeyCenter {
    private var refs: [EventHotKeyRef?] = []
    private var handlers: [UInt32: () -> Void] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?
    private let signature: OSType = 0x416E6368   // 'Anch'

    init() { installHandler() }

    deinit {
        unregisterAll()
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    private func installHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
            center.handlers[hkID.id]?()
            return noErr
        }, 1, &spec, selfPtr, &eventHandler)
    }

    /// Register one shortcut. Returns false if registration failed (e.g. already taken system-wide).
    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) -> Bool {
        let hkID = EventHotKeyID(signature: signature, id: nextID)
        var ref: EventHotKeyRef?
        guard RegisterEventHotKey(keyCode, modifiers, hkID, GetApplicationEventTarget(), 0, &ref) == noErr else {
            return false
        }
        handlers[nextID] = handler
        refs.append(ref)
        nextID += 1
        return true
    }

    func unregisterAll() {
        for ref in refs where ref != nil { UnregisterEventHotKey(ref) }
        refs.removeAll()
        handlers.removeAll()
    }
}
