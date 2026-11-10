import AppKit
import Carbon.HIToolbox

enum KeyCodeMap {
    static func name(for keyCode: Int) -> String {
        if let name = specialKeyName(for: keyCode) {
            return name
        }
        // The number row is named by its digits on every layout, as macOS does
        // for ⇧⌘3, even where the digits are the shifted characters (AZERTY).
        if let digit = digitRowName(for: keyCode) {
            return digit
        }
        // Key codes identify physical positions; what is printed on a key
        // depends on the keyboard layout (kVK_ANSI_Q is "A" on AZERTY).
        if let character = layoutCharacter(for: keyCode) {
            return character
        }
        return ansiKeyName(for: keyCode) ?? "Key\(keyCode)"
    }

    /// The `NSMenuItem.keyEquivalent` string for a key, or nil when AppKit
    /// has no equivalent for it (keypad digits, unknown keys). Display names
    /// don't work for this: "←" is a character, not the arrow key.
    static func menuKeyEquivalent(for keyCode: Int) -> String? {
        if let equivalent = specialKeyEquivalent(for: keyCode) {
            return equivalent
        }
        guard specialKeyName(for: keyCode) == nil else { return nil }
        guard let name = digitRowName(for: keyCode) ?? layoutCharacter(for: keyCode) ?? ansiKeyName(for: keyCode),
              name.count == 1 else {
            return nil
        }
        return name.lowercased()
    }

    static func modifierSymbols(for flags: CGEventFlags) -> String {
        var symbols = ""
        if flags.contains(.maskControl) { symbols += "⌃" }
        if flags.contains(.maskAlternate) { symbols += "⌥" }
        if flags.contains(.maskShift) { symbols += "⇧" }
        if flags.contains(.maskCommand) { symbols += "⌘" }
        return symbols
    }

    /// Keys whose name does not depend on the keyboard layout.
    private static func specialKeyName(for keyCode: Int) -> String? {
        switch keyCode {
        case kVK_Return: return "Return"
        case kVK_Tab: return "Tab"
        case kVK_Space: return "Space"
        case kVK_Delete: return "Delete"
        case kVK_ForwardDelete: return "Forward Delete"
        case kVK_Escape: return "Escape"
        case kVK_Home: return "Home"
        case kVK_End: return "End"
        case kVK_PageUp: return "Page Up"
        case kVK_PageDown: return "Page Down"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        case kVK_F13: return "F13"
        case kVK_F14: return "F14"
        case kVK_F15: return "F15"
        case kVK_F16: return "F16"
        case kVK_F17: return "F17"
        case kVK_F18: return "F18"
        case kVK_F19: return "F19"
        case kVK_F20: return "F20"
        // Keypad keys produce the same characters as the main row, so they
        // are named explicitly to keep the two apart.
        case kVK_ANSI_Keypad0: return "Keypad 0"
        case kVK_ANSI_Keypad1: return "Keypad 1"
        case kVK_ANSI_Keypad2: return "Keypad 2"
        case kVK_ANSI_Keypad3: return "Keypad 3"
        case kVK_ANSI_Keypad4: return "Keypad 4"
        case kVK_ANSI_Keypad5: return "Keypad 5"
        case kVK_ANSI_Keypad6: return "Keypad 6"
        case kVK_ANSI_Keypad7: return "Keypad 7"
        case kVK_ANSI_Keypad8: return "Keypad 8"
        case kVK_ANSI_Keypad9: return "Keypad 9"
        case kVK_ANSI_KeypadDecimal: return "Keypad ."
        case kVK_ANSI_KeypadMultiply: return "Keypad *"
        case kVK_ANSI_KeypadPlus: return "Keypad +"
        case kVK_ANSI_KeypadMinus: return "Keypad -"
        case kVK_ANSI_KeypadDivide: return "Keypad /"
        case kVK_ANSI_KeypadEquals: return "Keypad ="
        case kVK_ANSI_KeypadEnter: return "Keypad Enter"
        case kVK_ANSI_KeypadClear: return "Keypad Clear"
        default: return nil
        }
    }

    private static func specialKeyEquivalent(for keyCode: Int) -> String? {
        switch keyCode {
        case kVK_Return: return "\r"
        case kVK_Tab: return "\t"
        case kVK_Space: return " "
        case kVK_Escape: return "\u{1B}"
        // AppKit's naming is offset by one key: Delete is "backspace" and
        // Forward Delete is "delete".
        case kVK_Delete: return keyEquivalent(.backspace)
        case kVK_ForwardDelete: return keyEquivalent(.delete)
        case kVK_Home: return keyEquivalent(.home)
        case kVK_End: return keyEquivalent(.end)
        case kVK_PageUp: return keyEquivalent(.pageUp)
        case kVK_PageDown: return keyEquivalent(.pageDown)
        case kVK_LeftArrow: return keyEquivalent(.leftArrow)
        case kVK_RightArrow: return keyEquivalent(.rightArrow)
        case kVK_UpArrow: return keyEquivalent(.upArrow)
        case kVK_DownArrow: return keyEquivalent(.downArrow)
        case kVK_F1: return keyEquivalent(.f1)
        case kVK_F2: return keyEquivalent(.f2)
        case kVK_F3: return keyEquivalent(.f3)
        case kVK_F4: return keyEquivalent(.f4)
        case kVK_F5: return keyEquivalent(.f5)
        case kVK_F6: return keyEquivalent(.f6)
        case kVK_F7: return keyEquivalent(.f7)
        case kVK_F8: return keyEquivalent(.f8)
        case kVK_F9: return keyEquivalent(.f9)
        case kVK_F10: return keyEquivalent(.f10)
        case kVK_F11: return keyEquivalent(.f11)
        case kVK_F12: return keyEquivalent(.f12)
        case kVK_F13: return keyEquivalent(.f13)
        case kVK_F14: return keyEquivalent(.f14)
        case kVK_F15: return keyEquivalent(.f15)
        case kVK_F16: return keyEquivalent(.f16)
        case kVK_F17: return keyEquivalent(.f17)
        case kVK_F18: return keyEquivalent(.f18)
        case kVK_F19: return keyEquivalent(.f19)
        case kVK_F20: return keyEquivalent(.f20)
        default: return nil
        }
    }

    private static func keyEquivalent(_ key: NSEvent.SpecialKey) -> String {
        String(Character(key.unicodeScalar))
    }

    /// The unmodified character the current keyboard layout produces for a
    /// key, uppercased; nil for keys that produce nothing visible. Text Input
    /// Sources is main-thread only, so other threads get nil and fall back to
    /// the ANSI table.
    private static func layoutCharacter(for keyCode: Int) -> String? {
        guard (0..<128).contains(keyCode) else { return nil }
        guard Thread.isMainThread,
              let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let rawLayoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(rawLayoutData).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let capacity = characters.count
        let status = layoutData.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return OSStatus(paramErr)
            }
            return UCKeyTranslate(
                layout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysMask),
                &deadKeyState,
                capacity,
                &length,
                &characters
            )
        }
        guard status == noErr, length > 0 else { return nil }
        let string = String(utf16CodeUnits: characters, count: length)

        // Function and navigation keys translate to control or private-use
        // code points rather than something that can be shown.
        let invisible = CharacterSet.whitespacesAndNewlines.union(.controlCharacters)
        let isVisible = string.unicodeScalars.allSatisfy { scalar in
            !invisible.contains(scalar) && !(0xE000...0xF8FF).contains(scalar.value)
        }
        guard string.count == 1, isVisible else { return nil }
        let uppercased = string.uppercased()
        // "ß" uppercases to "SS".
        return uppercased.count == 1 ? uppercased : string
    }

    /// Names by ANSI (US QWERTY) key position, for when the layout can't be
    /// consulted.
    private static func ansiKeyName(for keyCode: Int) -> String? {
        switch keyCode {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Quote: return "'"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Slash: return "/"
        case kVK_ANSI_Grave: return "`"
        default: return digitRowName(for: keyCode)
        }
    }

    private static func digitRowName(for keyCode: Int) -> String? {
        switch keyCode {
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        default: return nil
        }
    }
}
