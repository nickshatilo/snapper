import AppKit
import Carbon.HIToolbox

final class HotkeyManager {
    private let appState: AppState
    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var retapTimer: Timer?
    private var permissionRetryTimer: Timer?
    private var hasLoggedMissingPermission = false
    private var hasShownEventTapFailurePrompt = false

    init(appState: AppState) {
        self.appState = appState
    }

    func start() {
        installEventTapIfAllowed()
        startPermissionRetry()
    }

    func stop() {
        retapTimer?.invalidate()
        retapTimer = nil
        permissionRetryTimer?.invalidate()
        permissionRetryTimer = nil
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private func startPermissionRetry() {
        guard permissionRetryTimer == nil else { return }
        permissionRetryTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.installEventTapIfAllowed()
        }
    }

    private func installEventTapIfAllowed() {
        guard eventTap == nil else { return }
        guard PermissionChecker.isAccessibilityGranted() else {
            if !hasLoggedMissingPermission {
                print("Accessibility permission not granted, hotkeys disabled")
                hasLoggedMissingPermission = true
            }
            return
        }

        hasLoggedMissingPermission = false
        installEventTap()
        if eventTap != nil {
            startHealthCheck()
        }
    }

    private func installEventTap() {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: hotkeyCallback,
            userInfo: selfPtr
        )

        guard let tap = eventTap else {
            print("Failed to create CGEvent tap")
            if !hasShownEventTapFailurePrompt {
                hasShownEventTapFailurePrompt = true
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.alertStyle = .warning
                    alert.messageText = "Hotkeys Need Input Monitoring"
                    alert.informativeText = "Snapper couldn't install global hotkeys. Enable Snapper in Privacy & Security > Input Monitoring, then relaunch Snapper."
                    alert.addButton(withTitle: "Open Settings")
                    alert.addButton(withTitle: "Cancel")
                    let response = alert.runModal()
                    if response == .alertFirstButtonReturn {
                        PermissionChecker.openInputMonitoringSettings()
                    }
                }
            }
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func startHealthCheck() {
        retapTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self, let tap = self.eventTap else { return }
            if !CGEvent.tapIsEnabled(tap: tap) {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
    }

    fileprivate func handleKeyEvent(_ event: CGEvent) -> CGEvent? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        let hasCmd = flags.contains(.maskCommand)
        let hasShift = flags.contains(.maskShift)

        guard hasCmd && hasShift else { return event }

        let action: HotkeyAction? = switch Int(keyCode) {
        case kVK_ANSI_3: .captureFullscreen
        case kVK_ANSI_4: .captureArea
        default: nil
        }

        guard let action else { return event }

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .startCapture, object: action.captureMode)
        }

        // Return nil to suppress the system screenshot
        return nil
    }
}

private func hotkeyCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let userInfo {
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
            if let tap = manager.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
        return Unmanaged.passUnretained(event)
    }

    guard type == .keyDown, let userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
    if let modifiedEvent = manager.handleKeyEvent(event) {
        return Unmanaged.passUnretained(modifiedEvent)
    }
    return nil
}
