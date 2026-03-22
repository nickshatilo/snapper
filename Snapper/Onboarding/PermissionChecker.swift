import AppKit
import ScreenCaptureKit

enum PermissionChecker {
    private static var lastScreenRecordingPromptAt: Date = .distantPast
    private static let screenRecordingPromptCooldown: TimeInterval = 10

    static func isAccessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    static func requestAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func isScreenCaptureGranted() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    static func requestScreenCapture() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    static func openScreenRecordingSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    static func openKeyboardShortcutSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts")!
        NSWorkspace.shared.open(url)
    }

    static func openInputMonitoringSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
    }

    @MainActor
    static func promptForScreenRecordingInSettings() {
        let now = Date()
        guard now.timeIntervalSince(lastScreenRecordingPromptAt) >= screenRecordingPromptCooldown else {
            return
        }
        lastScreenRecordingPromptAt = now

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Screen Recording Permission Required"
        alert.informativeText = "Enable Screen Recording for Snapper in System Settings > Privacy & Security > Screen Recording, then relaunch Snapper. If you recently reinstalled or changed signing, macOS may require granting it again."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            openScreenRecordingSettings()
        }
    }
}
