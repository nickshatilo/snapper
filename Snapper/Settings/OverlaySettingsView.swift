import SwiftUI

struct OverlaySettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        Form {
            Section("Quick Access Overlay") {
                Picker("Screen Corner", selection: $appState.overlayCorner) {
                    ForEach(OverlayCorner.allCases, id: \.self) { corner in
                        Text(corner.displayName).tag(corner)
                    }
                }
            }

            Section {
                Text("The overlay stays visible until manually dismissed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
