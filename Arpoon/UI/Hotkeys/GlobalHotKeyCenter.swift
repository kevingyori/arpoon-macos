import Carbon
import Foundation

@MainActor
final class GlobalHotKeyCenter {
    static let shared = GlobalHotKeyCenter()

    private var handlers: [UInt32: () -> Void] = [:]
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1
    private var eventHandlerRef: EventHandlerRef?
    private let signature: OSType = 0x41504850

    private init() {
        installHandler()
    }

    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) -> Bool {
        let id = nextID
        nextID += 1

        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr, let hotKeyRef else {
            return false
        }

        handlers[id] = handler
        hotKeyRefs[id] = hotKeyRef
        return true
    }

    func unregisterAll() {
        for hotKeyRef in hotKeyRefs.values {
            UnregisterEventHotKey(hotKeyRef)
        }

        handlers.removeAll()
        hotKeyRefs.removeAll()
    }

    private func installHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, eventRef, _ in
            guard let eventRef else {
                return noErr
            }

            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                eventRef,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )

            guard status == noErr else {
                return status
            }

            Task { @MainActor in
                GlobalHotKeyCenter.shared.invoke(id: hotKeyID.id)
            }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )
    }

    private func invoke(id: UInt32) {
        handlers[id]?()
    }
}
