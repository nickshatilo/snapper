import SwiftUI

struct FloatingSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        Form {
            Section("Floating Screenshots") {
                HStack {
                    Text("Default Opacity")
                    Slider(value: $appState.defaultPinnedOpacity, in: 0.1...1.0)
                    Text("\(Int(appState.defaultPinnedOpacity * 100))%")
                        .frame(width: 40)
                }
            }

            Section("Tips") {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Scroll to adjust opacity", systemImage: "scroll")
                    Label("Arrow keys to nudge position", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                    Label("Right-click for context menu", systemImage: "cursorarrow.click")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
