import AppKit
import ScreenCaptureKit

struct WindowInfo {
    let window: SCWindow
    let frame: CGRect
    let title: String?
    let appName: String?
    /// Focus to hand back once the capture is done (the selector activated Snapper).
    let focusRestorer: FocusRestorer?
}

final class WindowSelectorController {
    private var overlayWindows: [NSWindow] = []
    private var highlightOverlays: [WindowHighlightOverlay] = []
    private var windows: [SCWindow] = []
    private let completion: (WindowInfo?) -> Void
    private let failure: @MainActor (Error) -> Void
    private var mouseMonitor: Any?
    private var didFinish = false
    private var focusRestorer: FocusRestorer?

    /// `completion` receives the picked window, or nil when the user cancels
    /// (the previously frontmost app has already been restored in that case).
    /// `failure` is called on the main actor if the window list can't be loaded.
    init(
        completion: @escaping (WindowInfo?) -> Void,
        failure: @escaping @MainActor (Error) -> Void
    ) {
        self.completion = completion
        self.failure = failure
    }

    func show() {
        didFinish = false
        focusRestorer = FocusRestorer.captureCurrentFocus()
        Task {
            do {
                guard PermissionChecker.isScreenCaptureGranted() else {
                    throw CaptureError.permissionDenied
                }
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                let ownPID = ProcessInfo.processInfo.processIdentifier
                let candidates = content.windows.filter {
                    Self.isSelectable(
                        layer: $0.windowLayer,
                        size: $0.frame.size,
                        ownerPID: $0.owningApplication?.processID,
                        ownPID: ownPID
                    )
                }
                // SCShareableContent doesn't guarantee z-order; CGWindowList does
                // (front to back), so use it to order hit-testing.
                let zOrder = Self.frontToBackWindowIDs()
                let ordered = Self.sortedFrontToBack(candidates, id: \.windowID, zOrder: zOrder)
                await MainActor.run {
                    guard !self.didFinish else { return }
                    self.windows = ordered
                    self.setupOverlay()
                }
            } catch {
                await MainActor.run {
                    guard !self.didFinish else { return }
                    self.didFinish = true
                    self.close()
                    self.failure(error)
                }
            }
        }
    }

    @MainActor
    private func setupOverlay() {
        guard !NSScreen.screens.isEmpty else {
            finish(with: nil)
            return
        }

        // Install before activation so an early Escape is not missed.
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            return self.handleEvent(event) ? nil : event
        }

        for screen in NSScreen.screens {
            let window = WindowSelectorWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.level = .init(rawValue: Int(CGWindowLevelForKey(.maximumWindow)) - 1)
            window.isOpaque = false
            window.backgroundColor = NSColor.black.withAlphaComponent(0.01)
            window.ignoresMouseEvents = false
            window.acceptsMouseMovedEvents = true
            // Keep ownership under ARC via `overlayWindows`; don't let close() release the instance.
            window.isReleasedWhenClosed = false

            let overlay = WindowHighlightOverlay(
                frame: NSRect(origin: .zero, size: screen.frame.size)
            )
            window.contentView = overlay
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(overlay)
            overlayWindows.append(window)
            highlightOverlays.append(overlay)
        }

        // Without activation, Escape and mouse-moved events go to the previously
        // frontmost app and the local monitor never sees them.
        NSApp.activate(ignoringOtherApps: true)
        updateHighlight(at: NSEvent.mouseLocation)
    }

    /// Returns true when the event was consumed.
    private func handleEvent(_ event: NSEvent) -> Bool {
        switch event.type {
        case .mouseMoved:
            updateHighlight(at: NSEvent.mouseLocation)
            return false

        case .leftMouseDown:
            let mouseLocation = NSEvent.mouseLocation
            if let selectedWindow = hitTestWindow(atAppKitPoint: mouseLocation) {
                let info = WindowInfo(
                    window: selectedWindow,
                    frame: selectedWindow.frame,
                    title: selectedWindow.title,
                    appName: selectedWindow.owningApplication?.applicationName,
                    focusRestorer: focusRestorer
                )
                finish(with: info)
            } else {
                finish(with: nil)
            }
            return true

        case .keyDown:
            if event.keyCode == 53 { // Escape
                finish(with: nil)
                return true
            }
            return false

        default:
            return false
        }
    }

    private func updateHighlight(at mouseLocation: NSPoint) {
        let appKitFrame = hitTestWindow(atAppKitPoint: mouseLocation).map {
            CoordinateSpace.cgToAppKit($0.frame)
        }
        for overlay in highlightOverlays where overlay.highlightScreenFrame != appKitFrame {
            overlay.highlightScreenFrame = appKitFrame
            overlay.needsDisplay = true
        }
    }

    private func hitTestWindow(atAppKitPoint point: NSPoint) -> SCWindow? {
        let cgPoint = CoordinateSpace.appKitToCG(point)
        // `windows` is sorted front to back.
        return windows.first { $0.frame.contains(cgPoint) }
    }

    private func finish(with result: WindowInfo?) {
        guard !didFinish else { return }
        didFinish = true
        // Avoid tearing down windows while AppKit is still dispatching the current event.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.close()
            if result == nil {
                self.focusRestorer?.restore()
            }
            self.completion(result)
        }
    }

    func close() {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
        for window in overlayWindows {
            window.close()
        }
        overlayWindows.removeAll()
        highlightOverlays.removeAll()
    }

    /// Normal and floating/always-on-top app windows (layers 0 up to, not
    /// including, the Dock level) of a usable size, excluding Snapper's own
    /// windows (pins, overlays, HUD). The Dock, menu bar and system overlays sit
    /// at the Dock level or above; negative layers are desktop-level.
    static func isSelectable(layer: Int, size: CGSize, ownerPID: pid_t?, ownPID: pid_t) -> Bool {
        let dockLevel = Int(CGWindowLevelForKey(.dockWindow))
        guard layer >= 0, layer < dockLevel else { return false }
        guard size.width > 50, size.height > 50 else { return false }
        return ownerPID != ownPID
    }

    /// On-screen window IDs, front to back.
    private static func frontToBackWindowIDs() -> [CGWindowID] {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else {
            return []
        }
        return info.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value }
    }

    /// Stable-sorts `items` by their position in `zOrder` (front to back).
    /// Items missing from `zOrder` keep their relative order after the rest.
    static func sortedFrontToBack<T>(_ items: [T], id: (T) -> CGWindowID, zOrder: [CGWindowID]) -> [T] {
        var rank: [CGWindowID: Int] = [:]
        for (index, windowID) in zOrder.enumerated() where rank[windowID] == nil {
            rank[windowID] = index
        }
        return items.enumerated()
            .sorted { lhs, rhs in
                let lhsRank = rank[id(lhs.element)] ?? Int.max
                let rhsRank = rank[id(rhs.element)] ?? Int.max
                if lhsRank != rhsRank { return lhsRank < rhsRank }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}

/// Borderless windows can't become key by default; the selector needs key
/// status so Escape reaches the app's local event monitor.
private final class WindowSelectorWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
