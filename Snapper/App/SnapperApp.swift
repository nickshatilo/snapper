import SwiftUI

@main
struct SnapperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // The real Settings window is managed by AppDelegate.showSettingsWindow
        // (reachable from the status-item menu); a second SwiftUI-scene
        // settings window would duplicate it. An App still needs one scene.
        Settings {
            EmptyView()
        }
    }
}
