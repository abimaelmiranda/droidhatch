import AppKit
import DroidHatchFrameTransport

enum InputKeyMapping {
    static func isPlayPauseShortcut(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags
        guard modifiers.contains(.command),
              !modifiers.contains(.shift),
              !modifiers.contains(.option),
              !modifiers.contains(.control) else {
            return false
        }

        // Keep plain Return and Space available as regular Android keys.
        if event.keyCode == MacKeyboardLayout.returnKeyCode
            || event.keyCode == MacKeyboardLayout.spaceKeyCode
            || event.keyCode == MacKeyboardLayout.keypadEnterKeyCode {
            return true
        }
        return event.charactersIgnoringModifiers == "\r"
    }

    static func systemAction(forKeyCode keyCode: UInt16) -> InputSystemAction? {
        switch keyCode {
        case MacKeyboardLayout.escapeKeyCode:
            return .back
        default:
            return nil
        }
    }

    static func hidUsage(forKeyCode keyCode: UInt16) -> UInt16? {
        MacKeyboardLayout.hidUsageByKeyCode[keyCode]
    }

    static func modifierUsage(forKeyCode keyCode: UInt16) -> UInt16? {
        MacKeyboardLayout.modifierHidUsageByKeyCode[keyCode]
    }
}
