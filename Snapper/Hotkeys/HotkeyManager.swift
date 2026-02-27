import AppKit
import Carbon.HIToolbox

final class HotkeyManager {
    private let appState: AppState
    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var retapTimer: Timer?
    private var permissionRetryTimer: Timer?
    private var carbonHandlerRef: EventHandlerRef?
    private var carbonHotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var carbonHotkeyActionsByID: [UInt32: HotkeyAction] = [:]
    private var fallbackGlobalMonitor: Any?
    private var fallbackLocalMonitor: Any?
    private var hasLoggedMissingPermission = false
    private var hasShownEventTapFailurePrompt = false
    private var permissionRetryCount = 0
    private let maxPermissionRetries = 40
    private let carbonSignature = OSType(0x534E5052) // "SNPR"

    var hasActiveGlobalHotkeys: Bool {
        eventTap != nil || !carbonHotKeyRefs.isEmpty
    }

    init(appState: AppState) {
        self.appState = appState
    }

    deinit {
        stop()
    }

    func start() {
        installCarbonHotkeysIfNeeded()
        installEventTapIfAllowed()
        if eventTap == nil {
            installFallbackMonitorsIfNeeded()
        } else {
            removeFallbackMonitors()
        }
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
        removeFallbackMonitors()
        unregisterCarbonHotkeys()
    }

    private func startPermissionRetry() {
        guard permissionRetryTimer == nil, eventTap == nil else { return }
        permissionRetryCount = 0
        permissionRetryTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            self.permissionRetryCount += 1
            if self.permissionRetryCount >= self.maxPermissionRetries {
                timer.invalidate()
                self.permissionRetryTimer = nil
                return
            }
            self.installEventTapIfAllowed()
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
            removeFallbackMonitors()
            permissionRetryTimer?.invalidate()
            permissionRetryTimer = nil
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
        retapTimer?.invalidate()
        retapTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self, let tap = self.eventTap else { return }
            if !CGEvent.tapIsEnabled(tap: tap) {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
    }

    private func installFallbackMonitorsIfNeeded() {
        if fallbackGlobalMonitor == nil {
            fallbackGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handleFallbackHotkey(event)
            }
        }
        if fallbackLocalMonitor == nil {
            fallbackLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handleFallbackHotkey(event)
                return event
            }
        }
    }

    private func removeFallbackMonitors() {
        if let fallbackGlobalMonitor {
            NSEvent.removeMonitor(fallbackGlobalMonitor)
            self.fallbackGlobalMonitor = nil
        }
        if let fallbackLocalMonitor {
            NSEvent.removeMonitor(fallbackLocalMonitor)
            self.fallbackLocalMonitor = nil
        }
    }

    private func installCarbonHotkeysIfNeeded() {
        guard carbonHandlerRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
            carbonHotkeyCallback,
            1,
            &eventType,
            selfPtr,
            &carbonHandlerRef
        )

        guard installStatus == noErr else {
            print("Failed to install Carbon hotkey handler: \(installStatus)")
            carbonHandlerRef = nil
            return
        }

        registerCarbonHotkey(action: .captureFullscreen, id: 1)
        registerCarbonHotkey(action: .captureArea, id: 2)
    }

    private func registerCarbonHotkey(action: HotkeyAction, id: UInt32) {
        guard carbonHotKeyRefs[id] == nil else { return }
        guard let keyCode = keyCodeForAction(action) else { return }

        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: carbonSignature, id: id)
        let status = RegisterEventHotKey(
            keyCode,
            UInt32(cmdKey | shiftKey),
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr, let hotKeyRef else {
            print("Failed to register Carbon hotkey for \(action): \(status)")
            return
        }

        carbonHotKeyRefs[id] = hotKeyRef
        carbonHotkeyActionsByID[id] = action
    }

    private func unregisterCarbonHotkeys() {
        for (_, hotKeyRef) in carbonHotKeyRefs {
            UnregisterEventHotKey(hotKeyRef)
        }
        carbonHotKeyRefs.removeAll()
        carbonHotkeyActionsByID.removeAll()

        if let carbonHandlerRef {
            RemoveEventHandler(carbonHandlerRef)
            self.carbonHandlerRef = nil
        }
    }

    private func keyCodeForAction(_ action: HotkeyAction) -> UInt32? {
        switch action {
        case .captureFullscreen:
            return UInt32(kVK_ANSI_3)
        case .captureArea:
            return UInt32(kVK_ANSI_4)
        default:
            return nil
        }
    }

    fileprivate func handleCarbonHotkeyEvent(_ event: EventRef?) {
        // Event tap has priority because it can suppress system screenshots.
        if eventTap != nil {
            return
        }

        guard let event else { return }
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard status == noErr, hotKeyID.signature == carbonSignature else { return }
        guard let action = carbonHotkeyActionsByID[hotKeyID.id] else { return }
        postAction(action)
    }

    private func handleFallbackHotkey(_ event: NSEvent) {
        // Event tap has priority because it can suppress system screenshots.
        if eventTap != nil {
            return
        }

        let keyCode = Int(event.keyCode)
        let hasCommand = event.modifierFlags.contains(.command)
        let hasShift = event.modifierFlags.contains(.shift)

        if isCarbonHandledHotkey(keyCode: keyCode, hasCommand: hasCommand, hasShift: hasShift) {
            return
        }

        if isHUDHotkey(keyCode: keyCode, hasCommand: hasCommand, hasShift: hasShift) {
            postShowAllInOneHUD()
            return
        }

        let action = actionForHotkey(
            keyCode: keyCode,
            hasCommand: hasCommand,
            hasShift: hasShift
        )
        guard let action else { return }
        postAction(action)
    }

    private func postAction(_ action: HotkeyAction) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .startCapture, object: action.captureMode)
        }
    }

    private func actionForHotkey(keyCode: Int, hasCommand: Bool, hasShift: Bool) -> HotkeyAction? {
        guard hasCommand && hasShift else { return nil }
        switch keyCode {
        case kVK_ANSI_3: return .captureFullscreen
        case kVK_ANSI_4: return .captureArea
        default: return nil
        }
    }

    private func isCarbonHandledHotkey(keyCode: Int, hasCommand: Bool, hasShift: Bool) -> Bool {
        guard !carbonHotKeyRefs.isEmpty else { return false }
        return hasCommand && hasShift && (keyCode == kVK_ANSI_3 || keyCode == kVK_ANSI_4)
    }

    private func isHUDHotkey(keyCode: Int, hasCommand: Bool, hasShift: Bool) -> Bool {
        hasCommand && hasShift && keyCode == kVK_ANSI_5
    }

    private func postShowAllInOneHUD() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .showAllInOneHUD, object: nil)
        }
    }

    fileprivate func handleKeyEvent(_ event: CGEvent) -> CGEvent? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        if isHUDHotkey(
            keyCode: Int(keyCode),
            hasCommand: flags.contains(.maskCommand),
            hasShift: flags.contains(.maskShift)
        ) {
            postShowAllInOneHUD()
            return nil
        }

        let action = actionForHotkey(
            keyCode: Int(keyCode),
            hasCommand: flags.contains(.maskCommand),
            hasShift: flags.contains(.maskShift)
        )
        guard let action else { return event }
        postAction(action)

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

private func carbonHotkeyCallback(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else { return noErr }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
    manager.handleCarbonHotkeyEvent(event)
    return noErr
}
