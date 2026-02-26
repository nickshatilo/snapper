import SwiftUI
import ServiceManagement

struct GeneralSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        Form {
            Section("Startup") {
                Toggle("Launch at login", isOn: $appState.launchAtLogin)
                    .onChange(of: appState.launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }
            }

            Section("Menu Bar") {
                Toggle("Show menu bar icon", isOn: $appState.menuBarVisible)
                    .onChange(of: appState.menuBarVisible) { _, isVisible in
                        NotificationCenter.default.post(name: .menuBarVisibilityChanged, object: isVisible)
                    }
            }

            Section("After Capture") {
                Toggle("Play capture sound", isOn: $appState.captureSound)
                if appState.captureSound {
                    HStack {
                        Picker("Capture sound", selection: $appState.captureSoundName) {
                            ForEach(CaptureSound.allCases, id: \.self) { sound in
                                Text(sound.displayName).tag(sound)
                            }
                        }
                        Button("Preview") {
                            SoundPlayer.playCapture(appState.captureSoundName)
                        }
                    }
                }
                Toggle("Copy to clipboard", isOn: $appState.copyToClipboard)
                Toggle("Save to file", isOn: $appState.saveToFile)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to set launch at login: \(error)")
        }
    }
}
