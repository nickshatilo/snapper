import AppKit

struct TimerCaptureRequest {
    static let `default` = TimerCaptureRequest(seconds: 3, mode: .fullscreen)

    let seconds: Int
    let mode: CaptureMode

    var normalizedSeconds: Int {
        max(1, seconds)
    }

    var normalizedMode: CaptureMode {
        mode == .timer ? .fullscreen : mode
    }
}

final class TimerCaptureController {
    private let notificationCenter: NotificationCenter
    private var countdownWindow: NSWindow?
    private var timer: Timer?
    private var observerToken: NSObjectProtocol?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
        observerToken = notificationCenter.addObserver(
            forName: .startTimerCapture,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let request = notification.object as? TimerCaptureRequest ?? .default
            self?.start(seconds: request.normalizedSeconds, mode: request.normalizedMode)
        }
    }

    deinit {
        cancelExistingCountdown()
        if let observerToken {
            notificationCenter.removeObserver(observerToken)
        }
    }

    func start(seconds: Int, mode: CaptureMode) {
        cancelExistingCountdown()
        guard showCountdown(seconds: seconds, completion: { [notificationCenter] in
            notificationCenter.post(name: .timerCaptureDidFinish, object: mode)
        }) else {
            notificationCenter.post(name: .timerCaptureDidFinish, object: nil)
            return
        }
    }

    private func cancelExistingCountdown() {
        removeEscapeMonitors()
        timer?.invalidate()
        timer = nil
        countdownWindow?.close()
        countdownWindow = nil
    }

    /// Abandons the running countdown. A nil mode tells the capture
    /// coordinator to release the reservation it made for this capture.
    private func cancelCountdown() {
        guard timer != nil else { return }
        cancelExistingCountdown()
        notificationCenter.post(name: .timerCaptureDidFinish, object: nil)
    }

    @discardableResult
    private func showCountdown(seconds: Int, completion: @escaping () -> Void) -> Bool {
        guard let screen = NSScreen.main else { return false }

        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        // The window is closed while `countdownWindow` still holds it; the
        // AppKit default (release on close) would then release it twice.
        window.isReleasedWhenClosed = false
        window.level = .init(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true

        let countdownView = CountdownOverlayView(frame: screen.frame)
        window.contentView = countdownView
        window.makeKeyAndOrderFront(nil)
        countdownWindow = window

        var remaining = seconds
        countdownView.setCountdown(remaining, total: seconds)

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            remaining -= 1
            if remaining <= 0 {
                timer.invalidate()
                self?.cancelExistingCountdown()
                completion()
            } else {
                countdownView.setCountdown(remaining, total: seconds)
            }
        }
        installEscapeMonitors()
        return true
    }

    /// Escape cancels the countdown. Another app is usually frontmost while
    /// it runs, so this needs a global monitor (delivered only when Snapper is
    /// trusted for Accessibility); the local one covers Snapper itself being
    /// active.
    private func installEscapeMonitors() {
        removeEscapeMonitors()
        let escapeKeyCode: UInt16 = 53
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == escapeKeyCode {
                self?.cancelCountdown()
            }
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == escapeKeyCode, let self, self.timer != nil else { return event }
            self.cancelCountdown()
            return nil
        }
    }

    private func removeEscapeMonitors() {
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
            self.globalKeyMonitor = nil
        }
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
    }
}
