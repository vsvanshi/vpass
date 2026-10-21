import Carbon.HIToolbox
import OSLog

private let hotKeyLog = Logger(subsystem: "com.varunsuryawanshi.vpass", category: "hotkey")

/// A system-wide keyboard shortcut. Carbon's RegisterEventHotKey works inside
/// the sandbox and, unlike an NSEvent global monitor, needs no Accessibility
/// permission.
@MainActor
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: @MainActor () -> Void

    init(keyCode: Int, modifiers: Int, action: @escaping @MainActor () -> Void) {
        self.action = action
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else {
                    return noErr
                }
                // Carbon delivers hot key events on the main thread.
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                MainActor.assumeIsolated {
                    hotKey.action()
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        let hotKeyID = EventHotKeyID(signature: OSType(0x5650_4153), id: 1) // "VPAS"
        let registerStatus = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if installStatus != noErr || registerStatus != noErr {
            hotKeyLog.error("Could not register the quick search shortcut (handler \(installStatus, privacy: .public), hot key \(registerStatus, privacy: .public))")
        }
    }
}
