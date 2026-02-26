import AppKit
import SwiftUI

final class OnboardingWindowController: NSWindowController {
    convenience init(appState: AppState) {
        let content = OnboardingView()
            .environment(appState)
        let hostingController = NSHostingController(rootView: content)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Welcome to Snapper"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()

        self.init(window: window)
    }
}
