import Carbon
import Foundation

private enum HotKeyConstants {
    static let signature = OSType(fourChar("NTCH"))
    static let toggleID: UInt32 = 1
    static let clipNoteID: UInt32 = 2
}

/// System-wide shortcuts that do not need Accessibility permission.
final class GlobalHotKey: @unchecked Sendable {
    static let shared = GlobalHotKey()
    static let displayName = "⌃⌥Space"
    static let clipNoteName = "⌃⌥N"

    var onPressed: (@MainActor () -> Void)?
    var onClipToNote: (@MainActor () -> Void)?

    private var toggleRef: EventHotKeyRef?
    private var clipNoteRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    func register() {
        unregister()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let installed = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ in
                guard let event else { return noErr }
                var identifier = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &identifier
                )
                guard status == noErr else { return noErr }
                guard identifier.signature == HotKeyConstants.signature else { return noErr }
                let hotKeyID = identifier.id
                DispatchQueue.main.async {
                    Task { @MainActor in
                        if hotKeyID == HotKeyConstants.toggleID {
                            GlobalHotKey.shared.onPressed?()
                        } else if hotKeyID == HotKeyConstants.clipNoteID {
                            GlobalHotKey.shared.onClipToNote?()
                        }
                    }
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &handlerRef
        )
        guard installed == noErr else { return }

        RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(controlKey | optionKey),
            EventHotKeyID(signature: HotKeyConstants.signature, id: HotKeyConstants.toggleID),
            GetApplicationEventTarget(),
            0,
            &toggleRef
        )
        RegisterEventHotKey(
            UInt32(kVK_ANSI_N),
            UInt32(controlKey | optionKey),
            EventHotKeyID(signature: HotKeyConstants.signature, id: HotKeyConstants.clipNoteID),
            GetApplicationEventTarget(),
            0,
            &clipNoteRef
        )
    }

    func unregister() {
        if let toggleRef {
            UnregisterEventHotKey(toggleRef)
            self.toggleRef = nil
        }
        if let clipNoteRef {
            UnregisterEventHotKey(clipNoteRef)
            self.clipNoteRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }
}

private func fourChar(_ string: String) -> UInt32 {
    var value: UInt32 = 0
    for byte in string.utf8.prefix(4) {
        value = (value << 8) + UInt32(byte)
    }
    return value
}
