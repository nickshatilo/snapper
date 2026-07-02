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
    private var bindingsObserver: NSObjectProtocol?
    private var hasLoggedMissingPermission = false
    private var hasShownEventTapFailurePrompt = false
    private var permissionRetryCount = 0
    private let maxPermissionRetries = 40
    private let carbonSignature = OSType(0x534E5052) // "SNPR"

    /// Current user bindings, kept in sync with AppState.
    private var bindings: [HotkeyAction: HotkeyBinding] = [:]
    /// Guards against the same physical key press being delivered through two
    /// paths at once (event tap + Carbon, or Carbon + NSEvent fallback).
    private var lastDispatched: (action: HotkeyAction, at: Date)?

    var hasActiveGlobalHotkeys: Bool {
        eventTap != nil || !carbonHotKeyRefs.isEmpty
    }

    init(appState: AppState) {
        self.appState = appState
        self.bindings = appState.hotkeyBindings
        bindingsObserver = NotificationCenter.default.addObserver(
            forName: .hotkeyBindingsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reloadBindings()
        }
    }

    deinit {
        if let bindingsObserver {
            NotificationCenter.default.removeObserver(bindingsObserver)
        }
        stop()
    }

    func start() {
        bindings = appState.hotkeyBindings
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

    private func reloadBindings() {
        bindings = appState.hotkeyBindings
        if carbonHandlerRef != nil {
            unregisterCarbonHotkeyRefs()
            registerCarbonHotkeys()
        }
    }

    // MARK: - Matching & dispatch

    private func action(forKeyCode keyCode: Int, flags: CGEventFlags) -> HotkeyAction? {
        bindings.first(where: { $0.value.matches(keyCode: keyCode, flags: flags) })?.key
    }

    fileprivate func dispatch(_ action: HotkeyAction) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let now = Date()
            if let last = self.lastDispatched,
               last.action == action,
               now.timeIntervalSince(last.at) < 0.25 {
                return
            }
            self.lastDispatched = (action, now)

            switch action {
            case .allInOneHUD:
                NotificationCenter.default.post(name: .showAllInOneHUD, object: nil)
            case .toggleDesktopIcons:
                DesktopIconsHelper.toggle()
            default:
                if let mode = action.captureMode {
                    NotificationCenter.default.post(name: .startCapture, object: mode)
                }
            }
        }
    }

    // MARK: - CGEvent tap (primary path; can suppress system shortcuts)

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

    fileprivate func handleKeyEvent(_ event: CGEvent) -> CGEvent? {
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        guard let action = action(forKeyCode: keyCode, flags: event.flags) else {
            return event
        }
        dispatch(action)
        // Suppress the event so a colliding system shortcut (e.g. ⌘⇧3)
        // doesn't also fire.
        return nil
    }

    // MARK: - Carbon hotkeys (backup path)

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

        registerCarbonHotkeys()
    }

    private func registerCarbonHotkeys() {
        var nextID: UInt32 = 1
        for (action, binding) in bindings.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            var hotKeyRef: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: carbonSignature, id: nextID)
            let status = RegisterEventHotKey(
                UInt32(binding.keyCode),
                carbonModifiers(from: binding.modifiers),
                hotKeyID,
                GetEventDispatcherTarget(),
                0,
                &hotKeyRef
            )

            if status == noErr, let hotKeyRef {
                carbonHotKeyRefs[nextID] = hotKeyRef
                carbonHotkeyActionsByID[nextID] = action
            } else {
                print("Failed to register Carbon hotkey for \(action): \(status)")
            }
            nextID += 1
        }
    }

    private func carbonModifiers(from flags: CGEventFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.maskCommand) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.maskShift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.maskAlternate) { modifiers |= UInt32(optionKey) }
        if flags.contains(.maskControl) { modifiers |= UInt32(controlKey) }
        return modifiers
    }

    private func unregisterCarbonHotkeyRefs() {
        for (_, hotKeyRef) in carbonHotKeyRefs {
            UnregisterEventHotKey(hotKeyRef)
        }
        carbonHotKeyRefs.removeAll()
        carbonHotkeyActionsByID.removeAll()
    }

    private func unregisterCarbonHotkeys() {
        unregisterCarbonHotkeyRefs()

        if let carbonHandlerRef {
            RemoveEventHandler(carbonHandlerRef)
            self.carbonHandlerRef = nil
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
        dispatch(action)
    }

    // MARK: - NSEvent fallback (no Accessibility permission)

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

    private func handleFallbackHotkey(_ event: NSEvent) {
        // Event tap has priority because it can suppress system screenshots.
        if eventTap != nil {
            return
        }

        // Handle every binding here rather than deferring to Carbon: the
        // system-reserved screenshot shortcuts (⌘⇧3/⌘⇧4) never reach
        // RegisterEventHotKey handlers, and dispatch() dedups the rest.
        let flags = cgEventFlags(from: event.modifierFlags)
        guard let action = action(forKeyCode: Int(event.keyCode), flags: flags) else { return }
        dispatch(action)
    }

    private func cgEventFlags(from flags: NSEvent.ModifierFlags) -> CGEventFlags {
        var result = CGEventFlags()
        if flags.contains(.command) { result.insert(.maskCommand) }
        if flags.contains(.shift) { result.insert(.maskShift) }
        if flags.contains(.option) { result.insert(.maskAlternate) }
        if flags.contains(.control) { result.insert(.maskControl) }
        return result
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
    handler: EventHandlerCallRef?,
    event: EventRef?,
    userInfo: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userInfo else { return OSStatus(eventNotHandledErr) }
    let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
    manager.handleCarbonHotkeyEvent(event)
    return noErr
}
