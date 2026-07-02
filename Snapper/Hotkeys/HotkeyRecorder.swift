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
}

final class HotkeyRecorderNSView: NSView {
    var onBindingCaptured: ((HotkeyBinding) -> Void)?
    private var isRecording = false
    private let textField = NSTextField()
    private var localMonitor: Any?

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
        isRecording = true
        textField.stringValue = "Press shortcut..."
        textField.textColor = .systemRed

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event)
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        textField.textColor = .labelColor
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        guard isRecording else { return }

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

        onBindingCaptured?(HotkeyBinding(keyCode: keyCode, modifiers: flags))
        stopRecording()
    }

    func updateDisplay(binding: HotkeyBinding?) {
        guard !isRecording else { return }
        textField.stringValue = binding?.displayString ?? ""
    }

    private static let functionKeyCodes: Set<Int> = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8,
        kVK_F9, kVK_F10, kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15,
        kVK_F16, kVK_F17, kVK_F18, kVK_F19,
    ]
}
