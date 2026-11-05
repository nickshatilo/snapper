import AppKit

/// Selection overlays activate Snapper so Escape and mouse-moved events reach
/// it. Once the overlay is gone, hand focus back to the app the user was in,
/// unless Snapper has since opened a window of its own (e.g. the editor).
struct FocusRestorer {
    private let previousApplication: NSRunningApplication?
    private let windowsAtStart: Set<ObjectIdentifier>

    /// Main thread only. Call before Snapper activates itself. Records nothing to restore when
    /// Snapper is already frontmost.
    static func captureCurrentFocus() -> FocusRestorer {
        let frontmost = NSWorkspace.shared.frontmostApplication
        let isSelf = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier
        return FocusRestorer(
            previousApplication: isSelf ? nil : frontmost,
            windowsAtStart: Set(documentWindows().map(ObjectIdentifier.init))
        )
    }

    func restore() {
        guard let application = previousApplication, !application.isTerminated, NSApp.isActive else { return }
        // Don't steal focus from a Snapper window opened during the capture.
        let openedNewWindow = Self.documentWindows().contains { !windowsAtStart.contains(ObjectIdentifier($0)) }
        guard !openedNewWindow else { return }
        NSApp.yieldActivation(to: application)
        application.activate(options: [])
    }

    private static func documentWindows() -> [NSWindow] {
        NSApp.windows.filter { $0.isVisible && $0.styleMask.contains(.titled) && !($0 is NSPanel) }
    }
}
