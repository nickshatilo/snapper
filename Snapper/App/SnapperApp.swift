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
        .commands {
            // The scene also installs the standard Settings… command, which
            // stays active for a menu bar app whenever one of its windows is
            // key. Left alone, ⌘, would open the empty scene above, so route
            // it to the real window instead.
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    NotificationCenter.default.post(name: .showSettings, object: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
