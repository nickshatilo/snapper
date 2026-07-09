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
        timer?.invalidate()
        countdownWindow?.close()
        countdownWindow = nil
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
        timer?.invalidate()
        timer = nil
        countdownWindow?.close()
        countdownWindow = nil
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
        window.level = .init(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true

        let countdownView = CountdownOverlayView(frame: screen.frame)
        window.contentView = countdownView
        window.makeKeyAndOrderFront(nil)
        countdownWindow = window

        var remaining = seconds
        countdownView.setCountdown(remaining)

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            remaining -= 1
            if remaining <= 0 {
                timer.invalidate()
                self?.timer = nil
                self?.countdownWindow?.close()
                self?.countdownWindow = nil
                completion()
            } else {
                countdownView.setCountdown(remaining)
            }
        }
        return true
    }
}
