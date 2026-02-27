import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private var menuBarController: MenuBarController?
    private var hotkeyManager: HotkeyManager?
    private var captureCoordinator: CaptureCoordinator?
    private var quickAccessManager: QuickAccessManager?
    private var pinnedScreenshotManager: PinnedScreenshotManager?
    private var historyManager: HistoryManager?
    private var historyBrowserWindow: HistoryBrowserWindow?
    private var ocrCaptureController: OCRCaptureController?
    private var timerCaptureController: TimerCaptureController?
    private var allInOneHUDPanel: AllInOneHUDPanel?
    private var updateManager: UpdateManager?
    private var onboardingWindowController: OnboardingWindowController?
    private var settingsWindow: NSWindow?
    private var observerTokens: [NSObjectProtocol] = []

    deinit {
        for token in observerTokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        ensureSingleInstance()
        ProcessInfo.processInfo.disableAutomaticTermination("Snapper should stay alive as a menu bar utility.")

        // Core services
        menuBarController = MenuBarController(appState: appState)
        hotkeyManager = HotkeyManager(appState: appState)
        captureCoordinator = CaptureCoordinator(appState: appState)

        // Keep the app reachable even when hotkey permissions are missing.
        if appState.menuBarVisible {
            menuBarController?.show()
        } else if PermissionChecker.isAccessibilityGranted() {
            menuBarController?.hide()
        } else {
            appState.menuBarVisible = true
            menuBarController?.show()
        }

        // Overlay & Pinned
        quickAccessManager = QuickAccessManager(appState: appState)
        pinnedScreenshotManager = PinnedScreenshotManager(appState: appState)

        // History
        historyManager = HistoryManager()
        if let historyManager {
            historyBrowserWindow = HistoryBrowserWindow(historyManager: historyManager)
        }

        // Advanced capture modes
        ocrCaptureController = OCRCaptureController()
        timerCaptureController = TimerCaptureController()
        allInOneHUDPanel = AllInOneHUDPanel()

        // Updates
        updateManager = UpdateManager()

        // History & editor notifications
        observeNotifications()

        // History retention cleanup
        Task { @MainActor in
            let days = appState.historyRetentionDays
            if days > 0 {
                historyManager?.deleteOlderThan(days: days)
            }
        }

        // First run
        if appState.isFirstRun {
            showOnboarding()
        }

        hotkeyManager?.start()
        enforceReachability()
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState.flushDefaults()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !appState.menuBarVisible {
            showSettingsWindow()
        }
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Retry enabling global hotkeys after users grant accessibility permission.
        hotkeyManager?.start()
        enforceReachability()
    }

    private func ensureSingleInstance() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)

        for runningApp in runningApps where runningApp.processIdentifier != currentPID {
            runningApp.activate(options: [.activateAllWindows])
            NSApp.terminate(nil)
            return
        }
    }

    private func showOnboarding() {
        onboardingWindowController = OnboardingWindowController(appState: appState)
        onboardingWindowController?.showWindow(nil)
    }

    private func observeNotifications() {
        let showHistoryToken = NotificationCenter.default.addObserver(forName: .showHistory, object: nil, queue: .main) { [weak self] _ in
            self?.historyBrowserWindow?.show()
        }
        observerTokens.append(showHistoryToken)

        let showSettingsToken = NotificationCenter.default.addObserver(forName: .showSettings, object: nil, queue: .main) { [weak self] _ in
            self?.showSettingsWindow()
        }
        observerTokens.append(showSettingsToken)

        let showOnboardingToken = NotificationCenter.default.addObserver(forName: .showOnboarding, object: nil, queue: .main) { [weak self] _ in
            self?.showOnboarding()
        }
        observerTokens.append(showOnboardingToken)

        let requestPermissionsToken = NotificationCenter.default.addObserver(forName: .requestPermissions, object: nil, queue: .main) { [weak self] _ in
            self?.requestPermissions()
        }
        observerTokens.append(requestPermissionsToken)

        let openEditorToken = NotificationCenter.default.addObserver(forName: .openEditor, object: nil, queue: .main) { notification in
            if let wrapper = notification.object as? ImageWrapper {
                AnnotationEditorWindow.open(with: wrapper.image)
            }
        }
        observerTokens.append(openEditorToken)

        let menuVisibilityToken = NotificationCenter.default.addObserver(
            forName: .menuBarVisibilityChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let isVisible = notification.object as? Bool else { return }
            guard let self else { return }

            if !isVisible, !(self.hotkeyManager?.hasActiveGlobalHotkeys ?? false) {
                self.appState.menuBarVisible = true
                self.menuBarController?.show()
                self.presentHotkeysUnavailableAlert()
                return
            }

            if isVisible {
                self.menuBarController?.show()
            } else {
                self.menuBarController?.hide()
            }
        }
        observerTokens.append(menuVisibilityToken)

        let historyRetentionToken = NotificationCenter.default.addObserver(
            forName: .historyRetentionChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let days = notification.object as? Int else { return }
            guard days > 0 else { return }
            self?.historyManager?.deleteOlderThan(days: days)
        }
        observerTokens.append(historyRetentionToken)

        let clearHistoryToken = NotificationCenter.default.addObserver(
            forName: .clearHistoryRequested,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.historyManager?.clearAll()
        }
        observerTokens.append(clearHistoryToken)

        // Save captures to history
        let captureCompletedToken = NotificationCenter.default.addObserver(
            forName: .captureCompleted,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let info = notification.object as? CaptureCompletedInfo,
                  let historyManager = self?.historyManager else { return }

            DispatchQueue.global(qos: .utility).async {
                let thumbnailURL = info.thumbnail.flatMap { historyManager.saveThumbnail($0, for: info.recordID) }
                historyManager.saveCapture(
                    result: info.result,
                    savedURL: info.savedURL,
                    thumbnailURL: thumbnailURL,
                    recordID: info.recordID,
                    fileSize: info.fileSize
                )
            }
        }
        observerTokens.append(captureCompletedToken)

        let deleteHistoryRecordToken = NotificationCenter.default.addObserver(
            forName: .deleteHistoryRecord,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let recordID = notification.object as? UUID else { return }
            self?.historyManager?.delete(recordID: recordID)
        }
        observerTokens.append(deleteHistoryRecordToken)
    }

    private func showSettingsWindow() {
        let window: NSWindow
        if let existingWindow = settingsWindow {
            window = existingWindow
        } else {
            let content = SettingsView()
                .environment(appState)
            let hostingController = NSHostingController(rootView: content)

            let newWindow = NSWindow(contentViewController: hostingController)
            newWindow.title = "Settings"
            newWindow.styleMask = [.titled, .closable, .miniaturizable]
            newWindow.isReleasedWhenClosed = false
            newWindow.setContentSize(NSSize(width: 680, height: 520))
            newWindow.center()
            settingsWindow = newWindow
            window = newWindow
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func requestPermissions() {
        NSApp.activate(ignoringOtherApps: true)
        if !PermissionChecker.isScreenCaptureGranted() {
            let screenGranted = PermissionChecker.requestScreenCapture()
            if !screenGranted {
                PermissionChecker.openScreenRecordingSettings()
            }
            return
        }

        if !PermissionChecker.isAccessibilityGranted() {
            let accessibilityGranted = PermissionChecker.requestAccessibility()
            if !accessibilityGranted {
                PermissionChecker.openAccessibilitySettings()
            }
            return
        }

        // Input Monitoring has no direct prompt API; users can grant it from Privacy settings if needed.
    }

    private func enforceReachability() {
        // If users hide the menu icon while no global hotkeys are active, the app becomes unreachable.
        guard !appState.menuBarVisible else { return }
        guard !(hotkeyManager?.hasActiveGlobalHotkeys ?? false) else { return }
        appState.menuBarVisible = true
        menuBarController?.show()
    }

    private func presentHotkeysUnavailableAlert() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Can't Hide Menu Bar Icon Yet"
        alert.informativeText = "Global hotkeys are not active. Keep the menu bar icon visible until Accessibility/Input Monitoring permissions are granted."
        alert.addButton(withTitle: "Open Permissions")
        alert.addButton(withTitle: "OK")
        if alert.runModal() == .alertFirstButtonReturn {
            requestPermissions()
            PermissionChecker.openInputMonitoringSettings()
        }
    }
}

extension Notification.Name {
    static let clearHistoryRequested = Notification.Name("clearHistoryRequested")
}
