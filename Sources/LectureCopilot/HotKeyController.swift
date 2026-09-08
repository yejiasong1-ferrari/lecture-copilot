import Carbon.HIToolbox
import AppKit
import Foundation

final class HotKeyController {
    var onHotKey: ((HotKeyEvent) -> Void)?
    var shouldHandleReturnKey: (() -> Bool)?

    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var returnHotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    func start() {
        installHandler()
        registerHotKey(keyCode: UInt32(kVK_LeftArrow), id: 1, action: .shiftLeft)
        registerHotKey(keyCode: UInt32(kVK_RightArrow), id: 2, action: .shiftRight)
        registerHotKey(keyCode: UInt32(kVK_UpArrow), id: 3, action: .shiftUp)
        registerHotKey(keyCode: UInt32(kVK_DownArrow), id: 4, action: .shiftDown)
        DebugLog.write("Carbon hotkeys registered")
    }

    func stop() {
        setReturnHotKeyEnabled(false)
        for hotKeyRef in hotKeyRefs {
            if let hotKeyRef {
                UnregisterEventHotKey(hotKeyRef)
            }
        }
        hotKeyRefs.removeAll()

        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
        eventHandler = nil
    }

    func setReturnHotKeyEnabled(_ enabled: Bool) {
        if enabled {
            guard returnHotKeyRef == nil else { return }
            let hotKeyID = EventHotKeyID(signature: fourCharCode("LCP0"), id: 5)
            var hotKeyRef: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(kVK_Return),
                UInt32(shiftKey),
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &hotKeyRef
            )
            if status == noErr {
                returnHotKeyRef = hotKeyRef
                DebugLog.write("Registered pending Shift+Return hotkey")
            } else {
                DebugLog.write("Register pending Shift+Return hotkey failed: \(status)")
            }
            return
        }

        guard let returnHotKeyRef else { return }
        UnregisterEventHotKey(returnHotKeyRef)
        self.returnHotKeyRef = nil
        DebugLog.write("Unregistered pending Shift+Return hotkey")
    }

    private func installHandler() {
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else {
                    return noErr
                }

                let controller = Unmanaged<HotKeyController>.fromOpaque(userData).takeUnretainedValue()
                controller.handleCarbonHotKey(event)
                return noErr
            },
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        if status != noErr {
            DebugLog.write("InstallEventHandler failed: \(status)")
        }
    }

    private func registerHotKey(keyCode: UInt32, id: UInt32, action: HotKeyEvent) {
        var hotKeyID = EventHotKeyID(signature: fourCharCode("LCP0"), id: id)
        var hotKeyRef: EventHotKeyRef?

        let status = RegisterEventHotKey(
            keyCode,
            UInt32(shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status == noErr {
            hotKeyRefs.append(hotKeyRef)
            DebugLog.write("Registered hotkey \(action)")
        } else {
            DebugLog.write("RegisterEventHotKey failed for \(action): \(status)")
        }
    }

    private func handleCarbonHotKey(_ event: EventRef) {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard status == noErr else {
            DebugLog.write("GetEventParameter failed: \(status)")
            return
        }

        let hotKeyEvent: HotKeyEvent?
        switch hotKeyID.id {
        case 1: hotKeyEvent = .shiftLeft
        case 2: hotKeyEvent = .shiftRight
        case 3: hotKeyEvent = .shiftUp
        case 4: hotKeyEvent = .shiftDown
        case 5: hotKeyEvent = shouldHandleReturnKey?() == true ? .returnKey : nil
        default: hotKeyEvent = nil
        }

        guard let hotKeyEvent else { return }
        DebugLog.write("Carbon hotkey received: \(hotKeyEvent)")
        onHotKey?(hotKeyEvent)
    }

    private func fourCharCode(_ string: String) -> OSType {
        string.utf8.reduce(0) { ($0 << 8) + OSType($1) }
    }
}
