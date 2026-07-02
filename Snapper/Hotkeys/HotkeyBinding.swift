import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// A user-assignable keyboard shortcut: a key code plus the exact set of
/// required modifier keys.
struct HotkeyBinding: Codable, Hashable {
    let keyCode: Int
    let modifierRawValue: UInt64

    init(keyCode: Int, modifiers: CGEventFlags) {
        self.keyCode = keyCode
        self.modifierRawValue = Self.relevantModifiers(from: modifiers).rawValue
    }

    var modifiers: CGEventFlags {
        CGEventFlags(rawValue: modifierRawValue)
    }

    var displayString: String {
        KeyCodeMap.modifierSymbols(for: modifiers) + KeyCodeMap.name(for: keyCode)
    }

    /// The modifier keys a binding can meaningfully require. Device-dependent
    /// and lock bits are ignored when matching.
    static let consideredModifiers: CGEventFlags = [
        .maskCommand, .maskShift, .maskAlternate, .maskControl,
    ]

    static func relevantModifiers(from flags: CGEventFlags) -> CGEventFlags {
        flags.intersection(consideredModifiers)
    }

    /// Exact-modifier matching: the event's considered modifiers must equal
    /// the binding's. A ⌘⇧4 binding must not swallow ⌘⌃⇧4 (macOS's own
    /// clipboard-screenshot shortcut) or other apps' ⌘⌥⇧4.
    func matches(keyCode: Int, flags: CGEventFlags) -> Bool {
        self.keyCode == keyCode && Self.relevantModifiers(from: flags) == modifiers
    }
}

extension HotkeyBinding {
    static let defaultBindings: [HotkeyAction: HotkeyBinding] = [
        .captureFullscreen: HotkeyBinding(keyCode: kVK_ANSI_3, modifiers: [.maskCommand, .maskShift]),
        .captureArea: HotkeyBinding(keyCode: kVK_ANSI_4, modifiers: [.maskCommand, .maskShift]),
        .allInOneHUD: HotkeyBinding(keyCode: kVK_ANSI_5, modifiers: [.maskCommand, .maskShift]),
    ]
}

extension Notification.Name {
    static let hotkeyBindingsChanged = Notification.Name("hotkeyBindingsChanged")
}
