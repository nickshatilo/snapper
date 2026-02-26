import SwiftUI

struct HistorySettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var storageSize: String = "Calculating..."
    @State private var showClearConfirmation = false

    var body: some View {
        @Bindable var appState = appState
        Form {
            Section("Storage") {
                HStack {
                    Text("Location")
                    Spacer()
                    Text(Constants.App.historyDirectory.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                HStack {
                    Text("Storage Used")
                    Spacer()
                    Text(storageSize)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Retention") {
                Picker("Keep history for", selection: $appState.historyRetentionDays) {
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                    Text("1 year").tag(365)
                    Text("Forever").tag(0)
                }
            }

            Section {
                Button("Clear All History", role: .destructive) {
                    showClearConfirmation = true
                }
                .confirmationDialog("Clear all capture history?", isPresented: $showClearConfirmation) {
                    Button("Clear All", role: .destructive) {
                        clearHistory()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { calculateStorageSize() }
    }

    private func calculateStorageSize() {
        DispatchQueue.global().async {
            let size = directorySize(at: Constants.App.historyDirectory)
            let formatted = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
            DispatchQueue.main.async {
                storageSize = formatted
            }
        }
    }

    private func directorySize(at url: URL) -> Int {
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey])
        var total = 0
        while let fileURL = enumerator?.nextObject() as? URL {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += size
            }
        }
        return total
    }

    private func clearHistory() {
        try? FileManager.default.removeItem(at: Constants.App.historyDirectory)
        try? FileManager.default.createDirectory(at: Constants.App.historyDirectory, withIntermediateDirectories: true)
        calculateStorageSize()
    }
}
