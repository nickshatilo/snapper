import SwiftUI

struct EditorSettingsView: View {
    var body: some View {
        Form {
            Section("Defaults") {
                Picker("Default Tool", selection: .constant(ToolType.arrow)) {
                    ForEach(ToolType.allCases, id: \.self) { tool in
                        Text(tool.displayName).tag(tool)
                    }
                }

                ColorPicker("Default Annotation Color", selection: .constant(.red))
            }

            Section("Background Tool") {
                Text("Manage background templates in the editor.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
