import AppKit
import ServiceManagement
import SwiftUI

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case capture
    case overlay
    case history
    case shortcuts
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .capture: return "Capture"
        case .overlay: return "Overlay"
        case .history: return "History"
        case .shortcuts: return "Shortcuts"
        case .about: return "About"
        }
    }

    var iconName: String {
        switch self {
        case .general: return "gearshape"
        case .capture: return "camera"
        case .overlay: return "square.stack.3d.up"
        case .history: return "clock.arrow.circlepath"
        case .shortcuts: return "keyboard"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab: SettingsTab = .general
    @State private var storageSize: String = "Calculating..."
    @State private var showClearHistoryConfirmation = false

    var body: some View {
        @Bindable var appState = appState

        VStack(spacing: 0) {
            Text(selectedTab.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .padding(.top, 12)
                .padding(.bottom, 6)

            tabStrip
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch selectedTab {
                    case .general:
                        systemSection(appState: $appState)
                        usageSection(appState: $appState)
                    case .capture:
                        captureOutputSection(appState: $appState)
                        captureBehaviorSection(appState: $appState)
                    case .overlay:
                        overlaySection(appState: $appState)
                    case .history:
                        historyStorageSection(appState: $appState)
                        historyRetentionSection(appState: $appState)
                        historyActionsSection
                    case .shortcuts:
                        shortcutsSection
                    case .about:
                        aboutSection
                    }
                }
                .frame(maxWidth: 540, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }

            Divider()

            footer
        }
        .frame(width: 680, height: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            syncLaunchAtLoginState()
            calculateStorageSize()
        }
        .onChange(of: selectedTab) { _, tab in
            if tab == .history {
                calculateStorageSize()
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            HStack(spacing: 4) {
                Text("Made by Nick Shatilo")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("•")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Link("nickshatilo.com", destination: URL(string: "https://nickshatilo.com")!)
                    .font(.caption2)
            }
            Spacer()
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 12)
        .background(.bar)
    }

    private var tabStrip: some View {
        HStack {
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                ForEach(SettingsTab.allCases) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedTab = tab
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tab.iconName)
                                .font(.system(size: 17, weight: .semibold))
                            Text(tab.title)
                                .font(.caption)
                        }
                        .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                        .frame(width: 86, height: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(selectedTab == tab ? Color.primary.opacity(0.12) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private func systemSection(appState: Bindable<AppState>) -> some View {
        SettingsSection(title: "System") {
            ToggleRow(
                title: "Launch at Login",
                subtitle: "Automatically opens Snapper when your Mac starts.",
                isOn: launchAtLoginBinding(appState: appState)
            )

            ToggleRow(
                title: "Show Menu Bar Icon",
                subtitle: "Keep Snapper available from the menu bar at all times.",
                isOn: menuBarVisibilityBinding(appState: appState)
            )
        }
    }

    private func usageSection(appState: Bindable<AppState>) -> some View {
        SettingsSection(title: "Usage") {
            ToggleRow(
                title: "Play Capture Sound",
                subtitle: "Play a shutter sound after each successful capture.",
                isOn: appState.captureSound
            )

            if appState.captureSound.wrappedValue {
                RowWithTrailingControl(title: "Capture Sound") {
                    HStack(spacing: 8) {
                        Picker("Capture Sound", selection: appState.captureSoundName) {
                            ForEach(CaptureSound.allCases, id: \.self) { sound in
                                Text(sound.displayName).tag(sound)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 150)

                        Button("Preview") {
                            SoundPlayer.playCapture(appState.captureSoundName.wrappedValue)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            ToggleRow(
                title: "Copy to Clipboard",
                subtitle: "Immediately copy every capture image to the clipboard.",
                isOn: appState.copyToClipboard
            )

            ToggleRow(
                title: "Save to File",
                subtitle: "Automatically save every capture to your selected folder.",
                isOn: appState.saveToFile
            )
        }
    }

    private func captureOutputSection(appState: Bindable<AppState>) -> some View {
        SettingsSection(title: "Output") {
            RowWithTrailingControl(title: "Image Format") {
                Picker("Image Format", selection: appState.imageFormat) {
                    ForEach(ImageFormat.allCases, id: \.self) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .labelsHidden()
                .frame(width: 140)
            }

            if appState.imageFormat.wrappedValue == .jpeg {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 12) {
                        Text("JPEG Quality")
                        Spacer()
                        Slider(value: appState.jpegQuality, in: 0.1...1.0)
                            .frame(width: 180)
                        Text("\(Int(appState.jpegQuality.wrappedValue * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 42, alignment: .trailing)
                    }
                    Text("Higher quality means larger files.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Filename Pattern")
                    .fontWeight(.medium)
                TextField("Snapper {date} at {time}", text: appState.filenamePattern)
                    .textFieldStyle(.roundedBorder)
                Text("Use placeholders like {date} and {time}.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Save Directory")
                    .fontWeight(.medium)
                HStack(spacing: 10) {
                    Text(appState.saveDirectory.wrappedValue.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Choose…") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        if panel.runModal() == .OK, let url = panel.url {
                            appState.saveDirectory.wrappedValue = url
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func captureBehaviorSection(appState: Bindable<AppState>) -> some View {
        SettingsSection(title: "Behavior") {
            ToggleRow(
                title: "Show Crosshair Cursor",
                subtitle: "Display crosshair guides while selecting an area.",
                isOn: appState.showCrosshair
            )

            ToggleRow(
                title: "Show Magnifier",
                subtitle: "Zoom near the cursor for pixel-level area selection.",
                isOn: appState.showMagnifier
            )

            ToggleRow(
                title: "Freeze Screen During Selection",
                subtitle: "Capture from a frozen frame instead of a live desktop.",
                isOn: appState.freezeScreen
            )

            ToggleRow(
                title: "Retina 2x Captures",
                subtitle: "Save captures at native Retina resolution.",
                isOn: appState.retina2x
            )
        }
    }

    private func overlaySection(appState: Bindable<AppState>) -> some View {
        SettingsSection(title: "Quick Preview") {
            RowWithTrailingControl(title: "Screen Corner") {
                Picker("Screen Corner", selection: appState.overlayCorner) {
                    ForEach(OverlayCorner.allCases, id: \.self) { corner in
                        Text(corner.displayName).tag(corner)
                    }
                }
                .labelsHidden()
                .frame(width: 170)
            }

            Text("Preview thumbnails stay visible until you dismiss them.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func historyStorageSection(appState: Bindable<AppState>) -> some View {
        SettingsSection(title: "Storage") {
            RowWithTrailingControl(title: "Location") {
                Text(Constants.App.historyDirectory.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            RowWithTrailingControl(title: "Storage Used") {
                Text(storageSize)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func historyRetentionSection(appState: Bindable<AppState>) -> some View {
        SettingsSection(title: "Retention") {
            RowWithTrailingControl(title: "Keep History For") {
                Picker("Keep history for", selection: appState.historyRetentionDays) {
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                    Text("1 year").tag(365)
                    Text("Forever").tag(0)
                }
                .labelsHidden()
                .frame(width: 140)
                .onChange(of: appState.historyRetentionDays.wrappedValue) { _, days in
                    NotificationCenter.default.post(name: .historyRetentionChanged, object: days)
                }
            }
        }
    }

    private var historyActionsSection: some View {
        SettingsSection(title: "Actions", drawsDivider: false) {
            Button("Clear All History", role: .destructive) {
                showClearHistoryConfirmation = true
            }
            .buttonStyle(.bordered)
            .confirmationDialog("Clear all capture history?", isPresented: $showClearHistoryConfirmation) {
                Button("Clear All", role: .destructive) {
                    clearHistory()
                }
            }
        }
    }

    private var shortcutsSection: some View {
        SettingsSection(title: "Capture Shortcuts", drawsDivider: false) {
            ForEach(HotkeyAction.allCases, id: \.self) { action in
                RowWithTrailingControl(title: action.displayName) {
                    Text(defaultShortcut(for: action))
                        .font(.system(.caption, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    private var aboutSection: some View {
        SettingsSection(title: "About", drawsDivider: false) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 48, height: 48)
                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Snapper")
                        .font(.headline)
                    Text("Version \(appVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Check for Updates…") {
                    NotificationCenter.default.post(name: .checkForUpdates, object: nil)
                }
                .buttonStyle(.borderedProminent)
            }

            Text("Open source macOS screenshot tool.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private func launchAtLoginBinding(appState: Bindable<AppState>) -> Binding<Bool> {
        Binding(
            get: { appState.launchAtLogin.wrappedValue },
            set: { enabled in
                setLaunchAtLogin(enabled)
            }
        )
    }

    private func menuBarVisibilityBinding(appState: Bindable<AppState>) -> Binding<Bool> {
        Binding(
            get: { appState.menuBarVisible.wrappedValue },
            set: { isVisible in
                appState.menuBarVisible.wrappedValue = isVisible
                NotificationCenter.default.post(name: .menuBarVisibilityChanged, object: isVisible)
            }
        )
    }

    private func syncLaunchAtLoginState() {
        appState.launchAtLogin = (SMAppService.mainApp.status == .enabled)
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
        syncLaunchAtLoginState()
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

private struct SettingsSection<Content: View>: View {
    let title: String
    var drawsDivider: Bool = true
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.caption)
                .foregroundStyle(.secondary)

            content
        }
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) {
            if drawsDivider {
                Divider()
                    .allowsHitTesting(false)
            }
        }
    }
}

private struct ToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    var onChange: ((Bool) -> Void)?

    init(
        title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        onChange: ((Bool) -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
        self.onChange = onChange
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .fontWeight(.medium)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.checkbox)
        .onChange(of: isOn) { _, newValue in
            onChange?(newValue)
        }
    }
}

private struct RowWithTrailingControl<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .fontWeight(.medium)
                .frame(width: 150, alignment: .leading)
            content
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
