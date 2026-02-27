import AppKit

final class AreaSelectorWindowController {
    private var overlayWindows: [NSWindow] = []
    private var overlayViews: [AreaSelectorOverlayView] = []
    private var localKeyMonitor: Any?
    private var didFinish = false
    private let completion: (CGRect?) -> Void

    init(completion: @escaping (CGRect?) -> Void) {
        self.completion = completion
    }

    func show(freezeScreen: Bool, showMagnifier: Bool = false) {
        didFinish = false
        installKeyMonitor()
        // Delay activation until the current event cycle finishes (for menu-triggered captures).
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.didFinish else { return }
            NSApp.activate(ignoringOtherApps: true)
        }

        for screen in NSScreen.screens {
            let window = AreaSelectorWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.level = .init(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
            window.isOpaque = false
            window.backgroundColor = .clear
            window.ignoresMouseEvents = false
            window.acceptsMouseMovedEvents = true
            window.hasShadow = false
            // We manage the window lifetime via `overlayWindows`; avoid legacy release-on-close over-release.
            window.isReleasedWhenClosed = false

            let overlayView = AreaSelectorOverlayView(frame: screen.frame)
            overlayView.showsMagnifier = showMagnifier
            overlayView.frozenImage = freezeScreen ? captureImage(for: screen) : nil
            overlayView.onSelectionComplete = { [weak self] rect in
                guard let self else { return }
                // Convert from view coordinates to screen coordinates
                let screenRect = CGRect(
                    x: screen.frame.origin.x + rect.origin.x,
                    y: screen.frame.origin.y + rect.origin.y,
                    width: rect.width,
                    height: rect.height
                )
                self.finish(with: screenRect)
            }
            overlayView.onCancel = { [weak self] in
                self?.finish(with: nil)
            }

            window.contentView = overlayView
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(overlayView)
            overlayWindows.append(window)
            overlayViews.append(overlayView)
        }
    }

    func close() {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
        for window in overlayWindows {
            window.close()
        }
        overlayWindows.removeAll()
        overlayViews.removeAll()
    }

    private func installKeyMonitor() {
        guard localKeyMonitor == nil else { return }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { // Escape
                let discardedAnySelection = self.overlayViews.reduce(false) { partialResult, overlayView in
                    overlayView.discardSelection() || partialResult
                }
                if !discardedAnySelection {
                    self.finish(with: nil)
                }
                return nil
            }
            return event
        }
    }

    private func finish(with result: CGRect?) {
        guard !didFinish else { return }
        didFinish = true
        // Avoid tearing down windows while AppKit is still dispatching the current mouse/key event.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.close()
            self.completion(result)
        }
    }

    private func captureImage(for screen: NSScreen) -> CGImage? {
        guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return nil
        }
        return CGDisplayCreateImage(displayID)
    }
}

private final class AreaSelectorWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
