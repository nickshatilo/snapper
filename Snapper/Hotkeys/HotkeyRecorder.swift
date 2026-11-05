import SwiftUI
import AppKit
import Carbon.HIToolbox

struct HotkeyRecorder: NSViewRepresentable {
    let binding: HotkeyBinding?
    let onChange: (HotkeyBinding) -> Void

    func makeNSView(context: Context) -> HotkeyRecorderNSView {
        let view = HotkeyRecorderNSView()
        view.onBindingCaptured = onChange
        view.updateDisplay(binding: binding)
        return view
    }

    func updateNSView(_ nsView: HotkeyRecorderNSView, context: Context) {
        nsView.onBindingCaptured = onChange
        nsView.updateDisplay(binding: binding)
    }

    static func dismantleNSView(_ nsView: HotkeyRecorderNSView, coordinator: ()) {
        nsView.stopRecording()
    }
}

final class HotkeyRecorderNSView: NSView {
    /// The recorder currently capturing a shortcut, if any. HotkeyManager
    /// forwards bound combos here instead of firing them while it is set.
    private(set) static weak var activeRecorder: HotkeyRecorderNSView?

    var onBindingCaptured: ((HotkeyBinding) -> Void)?
    private var isRecording = false
    private let textField = NSTextField()
    private var localMonitor: Any?
    private var currentBinding: HotkeyBinding?
    private var windowObservers: [NSObjectProtocol] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupTextField()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    deinit {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        for observer in windowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        for observer in windowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        windowObservers.removeAll()

        guard let window else {
            stopRecording()
            return
        }
        // The Settings window is hidden, not destroyed, on close, so the view
        // never leaves it. Stop recording when the window closes or loses key
        // status; otherwise the app-wide key monitor keeps swallowing every
        // keystroke (e.g. in the editor) and records the next one.
        for name in [NSWindow.willCloseNotification, NSWindow.didResignKeyNotification] {
            windowObservers.append(
                NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    self?.stopRecording()
                }
            )
        }
    }

    private func setupTextField() {
        textField.isEditable = false
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel
        textField.alignment = .center
        textField.placeholderString = "Click to record"
        textField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(textField)
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: leadingAnchor),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor),
            textField.topAnchor.constraint(equalTo: topAnchor),
            textField.bottomAnchor.constraint(equalTo: bottomAnchor),
            textField.heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    override func mouseDown(with event: NSEvent) {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        guard window != nil else { return }
        // Only one recorder may capture at a time.
        if let other = Self.activeRecorder, other !== self {
            other.stopRecording()
        }
        isRecording = true
        Self.activeRecorder = self
        textField.stringValue = "Press shortcut..."
        textField.textColor = .systemRed

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            // Keys aimed at another window (or none) end recording and pass
            // through untouched.
            guard event.window === self.window else {
                self.stopRecording()
                return event
            }
            self.handleKeyDown(event)
            return nil
        }
    }

    func stopRecording() {
        if Self.activeRecorder === self {
            Self.activeRecorder = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        guard isRecording else { return }
        isRecording = false
        textField.textColor = .labelColor
        // Drop the "Press shortcut..." prompt; a newly captured binding
        // arrives through updateDisplay once SwiftUI re-renders.
        textField.stringValue = currentBinding?.displayString ?? ""
    }

    /// A combo that the global hotkey machinery intercepted before the local
    /// key monitor could see it.
    func receiveInterceptedBinding(_ binding: HotkeyBinding) {
        guard isRecording else { return }
        capture(binding)
    }

    private func handleKeyDown(_ event: NSEvent) {
        guard isRecording, !event.isARepeat else { return }

        let keyCode = Int(event.keyCode)
        if keyCode == kVK_Escape {
            stopRecording()
            return
        }

        var flags = CGEventFlags()
        if event.modifierFlags.contains(.command) { flags.insert(.maskCommand) }
        if event.modifierFlags.contains(.shift) { flags.insert(.maskShift) }
        if event.modifierFlags.contains(.option) { flags.insert(.maskAlternate) }
        if event.modifierFlags.contains(.control) { flags.insert(.maskControl) }

        // A global shortcut without modifiers would swallow plain typing;
        // only function keys are allowed bare.
        if HotkeyBinding.relevantModifiers(from: flags).isEmpty, !Self.functionKeyCodes.contains(keyCode) {
            return
        }

        capture(HotkeyBinding(keyCode: keyCode, modifiers: flags))
    }

    private func capture(_ binding: HotkeyBinding) {
        let callback = onBindingCaptured
        stopRecording()
        callback?(binding)
    }

    func updateDisplay(binding: HotkeyBinding?) {
        currentBinding = binding
        guard !isRecording else { return }
        textField.stringValue = binding?.displayString ?? ""
    }

    private static let functionKeyCodes: Set<Int> = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8,
        kVK_F9, kVK_F10, kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15,
        kVK_F16, kVK_F17, kVK_F18, kVK_F19,
    ]
}
