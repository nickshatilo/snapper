import SwiftUI

struct CaptureSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        Form {
            Section("File Output") {
                Picker("Format", selection: $appState.imageFormat) {
                    ForEach(ImageFormat.allCases, id: \.self) { format in
                        Text(format.displayName).tag(format)
                    }
                }

                if appState.imageFormat == .jpeg {
                    HStack {
                        Text("Quality")
                        Slider(value: $appState.jpegQuality, in: 0.1...1.0)
                        Text("\(Int(appState.jpegQuality * 100))%")
                            .frame(width: 40)
                    }
                }

                HStack {
                    Text("Filename Pattern")
                    TextField("Pattern", text: $appState.filenamePattern)
                        .textFieldStyle(.roundedBorder)
                }

                HStack {
                    Text("Save Directory")
                    Text(appState.saveDirectory.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Choose...") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        if panel.runModal() == .OK, let url = panel.url {
                            appState.saveDirectory = url
                        }
                    }
                }
            }

            Section("Capture Behavior") {
                Toggle("Show magnifier", isOn: $appState.showMagnifier)
                Toggle("Freeze screen during selection", isOn: $appState.freezeScreen)
                Toggle("Save at Retina resolution (2x)", isOn: $appState.retina2x)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
