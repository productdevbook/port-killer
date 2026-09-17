import AppKit
import Carbon.HIToolbox
import PortKillerKit

@safe
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    var action: (() -> Void)?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    private init() {}

    func register(_ shortcut: KeyShortcut?) {
        unregister()
        guard let shortcut else { return }
        installHandlerIfNeeded()
        var reference: EventHotKeyRef? = nil
        let identifier = EventHotKeyID(signature: OSType(0x504B_4C52), id: 1)
        let status = unsafe RegisterEventHotKey(UInt32(shortcut.carbonKeyCode), UInt32(shortcut.carbonModifiers), identifier, GetApplicationEventTarget(), 0, &reference)
        if status == noErr { unsafe hotKey = reference }
    }

    func unregister() {
        if let hotKey = unsafe hotKey {
            unsafe UnregisterEventHotKey(hotKey)
        }
        unsafe hotKey = nil
    }

    private func installHandlerIfNeeded() {
        guard unsafe handler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        var reference: EventHandlerRef?
        let status = unsafe InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            MainActor.assumeIsolated {
                HotKeyCenter.shared.action?()
            }
            return noErr
        }, 1, &eventType, nil, &reference)
        if status == noErr { unsafe handler = reference }
    }
}

enum ShortcutRecording {
    static func shortcut(from event: NSEvent) -> KeyShortcut? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers = 0
        if flags.contains(.command) { modifiers |= KeyShortcut.command }
        if flags.contains(.shift) { modifiers |= KeyShortcut.shift }
        if flags.contains(.option) { modifiers |= KeyShortcut.option }
        if flags.contains(.control) { modifiers |= KeyShortcut.control }
        let shortcut = KeyShortcut(carbonKeyCode: Int(event.keyCode), carbonModifiers: modifiers)
        return shortcut.hasModifier ? shortcut : nil
    }
}
