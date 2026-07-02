import AppKit

final class MenuBarMenu: NSMenu {
    private let appState: AppState
    private var bindingsObserver: NSObjectProtocol?

    init(appState: AppState) {
        self.appState = appState
        super.init(title: "Snapper")
        buildMenu()
        bindingsObserver = NotificationCenter.default.addObserver(
            forName: .hotkeyBindingsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.removeAllItems()
            self?.buildMenu()
        }
    }

    deinit {
        if let bindingsObserver {
            NotificationCenter.default.removeObserver(bindingsObserver)
        }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    private func buildMenu() {
        // Capture modes; key equivalents mirror the user's actual bindings.
        let captureHeader = NSMenuItem(title: "Capture", action: nil, keyEquivalent: "")
        captureHeader.isEnabled = false
        addItem(captureHeader)

        addItem(makeItem("Capture Fullscreen", action: #selector(captureFullscreen), hotkeyAction: .captureFullscreen))
        addItem(makeItem("Capture Area", action: #selector(captureArea), hotkeyAction: .captureArea))
        addItem(makeItem("All-in-One HUD", action: #selector(showAllInOneHUD), hotkeyAction: .allInOneHUD))
        addItem(makeItem("Capture Window", action: #selector(captureWindow), hotkeyAction: .captureWindow))
        addItem(makeItem("Capture Scroll", action: #selector(captureScroll), hotkeyAction: .captureScroll))

        addItem(NSMenuItem.separator())

        addItem(makeItem("Timer Capture", action: #selector(timerCapture), hotkeyAction: .timerCapture))

        addItem(NSMenuItem.separator())

        addItem(makeItem("Toggle Desktop Icons", action: #selector(toggleDesktopIcons), hotkeyAction: .toggleDesktopIcons))

        addItem(NSMenuItem.separator())

        // History & Settings deliberately have no key equivalents: equivalents
        // in a status-item menu only fire while the menu is open, so showing
        // them would advertise shortcuts that don't work.
        addItem(makeItem("History", action: #selector(showHistory)))

        addItem(NSMenuItem.separator())

        addItem(makeItem("Privacy Permissions...", action: #selector(showPermissions)))
        addItem(makeItem("Settings...", action: #selector(showSettings)))
        addItem(makeItem("Check for Updates...", action: #selector(checkForUpdates)))

        addItem(NSMenuItem.separator())

        let quitItem = makeItem("Quit Snapper", action: #selector(quitApp))
        quitItem.keyEquivalent = "q"
        quitItem.keyEquivalentModifierMask = [.command]
        addItem(quitItem)
    }

    private func makeItem(_ title: String, action: Selector, hotkeyAction: HotkeyAction? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        if let hotkeyAction, let binding = appState.hotkeyBindings[hotkeyAction] {
            let keyName = KeyCodeMap.name(for: binding.keyCode)
            if keyName.count == 1 {
                item.keyEquivalent = keyName.lowercased()
                item.keyEquivalentModifierMask = modifierFlags(from: binding.modifiers)
            }
        }
        item.target = self
        return item
    }

    private func modifierFlags(from flags: CGEventFlags) -> NSEvent.ModifierFlags {
        var result: NSEvent.ModifierFlags = []
        if flags.contains(.maskCommand) { result.insert(.command) }
        if flags.contains(.maskShift) { result.insert(.shift) }
        if flags.contains(.maskAlternate) { result.insert(.option) }
        if flags.contains(.maskControl) { result.insert(.control) }
        return result
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

    @objc private func captureScroll() {
        NotificationCenter.default.post(name: .startCapture, object: CaptureMode.scroll)
    }

    @objc private func showAllInOneHUD() {
        NotificationCenter.default.post(name: .showAllInOneHUD, object: nil)
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
