import AppKit

final class MenuBarMenu: NSMenu {
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
        super.init(title: "Snapper")
        buildMenu()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    private func buildMenu() {
        // Capture modes
        let captureHeader = NSMenuItem(title: "Capture", action: nil, keyEquivalent: "")
        captureHeader.isEnabled = false
        addItem(captureHeader)

        addItem(makeItem("Capture Fullscreen", action: #selector(captureFullscreen), key: "3", modifiers: [.command, .shift]))
        addItem(makeItem("Capture Area", action: #selector(captureArea), key: "4", modifiers: [.command, .shift]))
        addItem(makeItem("Capture Window", action: #selector(captureWindow), key: "", modifiers: []))

        addItem(NSMenuItem.separator())

        addItem(makeItem("Timer Capture", action: #selector(timerCapture), key: "", modifiers: []))

        addItem(NSMenuItem.separator())

        addItem(makeItem("Toggle Desktop Icons", action: #selector(toggleDesktopIcons), key: "", modifiers: []))

        addItem(NSMenuItem.separator())

        // History
        addItem(makeItem("History", action: #selector(showHistory), key: "h", modifiers: [.command, .shift]))

        addItem(NSMenuItem.separator())

        // Settings & Quit
        addItem(makeItem("Privacy Permissions...", action: #selector(showPermissions), key: "", modifiers: []))
        addItem(makeItem("Settings...", action: #selector(showSettings), key: ",", modifiers: [.command]))
        addItem(makeItem("Check for Updates...", action: #selector(checkForUpdates), key: "", modifiers: []))

        addItem(NSMenuItem.separator())

        addItem(makeItem("Quit Snapper", action: #selector(quitApp), key: "q", modifiers: [.command]))
    }

    private func makeItem(_ title: String, action: Selector, key: String, modifiers: NSEvent.ModifierFlags) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = self
        return item
    }

    @objc private func captureFullscreen() {
        NotificationCenter.default.post(name: .startCapture, object: CaptureMode.fullscreen)
    }

    @objc private func captureArea() {
        NotificationCenter.default.post(name: .startCapture, object: CaptureMode.area)
    }

    @objc private func captureWindow() {
        NotificationCenter.default.post(name: .startCapture, object: CaptureMode.window)
    }

    @objc private func timerCapture() {
        NotificationCenter.default.post(name: .startCapture, object: CaptureMode.timer)
    }

    @objc private func toggleDesktopIcons() {
        DesktopIconsHelper.toggle()
    }

    @objc private func showHistory() {
        NotificationCenter.default.post(name: .showHistory, object: nil)
    }

    @objc private func showSettings() {
        NotificationCenter.default.post(name: .showSettings, object: nil)
    }

    @objc private func showPermissions() {
        NotificationCenter.default.post(name: .requestPermissions, object: nil)
    }

    @objc private func checkForUpdates() {
        NotificationCenter.default.post(name: .checkForUpdates, object: nil)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

extension Notification.Name {
    static let startCapture = Notification.Name("startCapture")
    static let showHistory = Notification.Name("showHistory")
    static let showSettings = Notification.Name("showSettings")
    static let showOnboarding = Notification.Name("showOnboarding")
    static let requestPermissions = Notification.Name("requestPermissions")
    static let checkForUpdates = Notification.Name("checkForUpdates")
    static let captureCompleted = Notification.Name("captureCompleted")
    static let menuBarVisibilityChanged = Notification.Name("menuBarVisibilityChanged")
    static let overlayCornerChanged = Notification.Name("overlayCornerChanged")
    static let pinnedOpacityChanged = Notification.Name("pinnedOpacityChanged")
    static let historyRetentionChanged = Notification.Name("historyRetentionChanged")
}
