import SwiftUI

struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            Text("Snapper")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Version \(appVersion)")
                .foregroundStyle(.secondary)

            Text("Open source macOS screenshot tool")
                .foregroundStyle(.secondary)

            Divider()

            VStack(spacing: 8) {
                Link("GitHub Repository", destination: URL(string: Constants.App.githubURL)!)
                Text("MIT License")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
            }

            Spacer()

            Button("Check for Updates...") {
                NotificationCenter.default.post(name: .checkForUpdates, object: nil)
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
}
