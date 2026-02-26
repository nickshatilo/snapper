import SwiftUI

struct ShortcutsSettingsView: View {
    var body: some View {
        Form {
            Section("Capture Shortcuts") {
                ForEach(HotkeyAction.allCases, id: \.self) { action in
                    HStack {
                        Text(action.displayName)
                            .frame(width: 200, alignment: .leading)
                        Spacer()
                        Text(defaultShortcut(for: action))
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.quaternary)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            }

            Section {
                Button("Reset to Defaults") {
                    // Reset all shortcuts to defaults
                }
                .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func defaultShortcut(for action: HotkeyAction) -> String {
        switch action {
        case .captureFullscreen: return "⌘⇧3"
        case .captureArea: return "⌘⇧4"
        case .captureWindow: return "—"
        case .scrollingCapture: return "—"
        case .ocrCapture: return "—"
        case .timerCapture: return "—"
        case .toggleDesktopIcons: return "—"
        }
    }
}
