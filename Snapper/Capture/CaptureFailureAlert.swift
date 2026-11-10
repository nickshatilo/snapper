import AppKit

/// Tells the user about capture and save failures, which would otherwise only
/// reach the console of a menu-bar app nobody is watching.
enum CaptureFailureAlert {
    /// A burst of failures (a held hotkey, an unwritable folder) should show
    /// one alert, not a stack of them.
    private static let alertCooldown: TimeInterval = 10
    @MainActor private static var lastCaptureFailureAlertAt: Date = .distantPast
    @MainActor private static var lastSaveFailureAlertAt: Date = .distantPast
    /// `runModal()` keeps servicing the main queue, so a failure arriving while
    /// an alert is still up must not open a second one on top of it.
    @MainActor private static var isPresenting = false

    @MainActor
    static func presentCaptureFailure(_ error: Error, context: String) {
        let now = Date()
        guard !isPresenting, now.timeIntervalSince(lastCaptureFailureAlertAt) >= alertCooldown else {
            return
        }
        lastCaptureFailureAlertAt = now

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "\(context) failed"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        _ = runModal(alert)
    }

    @MainActor
    static func presentSaveFailure(directory: URL) {
        let now = Date()
        guard !isPresenting, now.timeIntervalSince(lastSaveFailureAlertAt) >= alertCooldown else {
            return
        }
        lastSaveFailureAlertAt = now

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn't Save Screenshot"
        alert.informativeText = "Snapper couldn't write the screenshot to \(directory.path). Check that the folder exists and is writable, or pick another folder in Settings → Capture."
        alert.addButton(withTitle: "Open Settings")
        // Only a button titled "Cancel" gets Escape for free.
        alert.addButton(withTitle: "OK").keyEquivalent = "\u{1b}"
        if runModal(alert) == .alertFirstButtonReturn {
            NotificationCenter.default.post(name: .showSettings, object: nil)
        }
    }

    @MainActor
    private static func runModal(_ alert: NSAlert) -> NSApplication.ModalResponse {
        isPresenting = true
        defer { isPresenting = false }
        // Snapper is usually in the background when a capture fails; without
        // activation the alert would open behind the frontmost app.
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal()
    }
}
