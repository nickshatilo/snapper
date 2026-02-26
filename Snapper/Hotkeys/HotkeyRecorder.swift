import SwiftUI
import AppKit
import Carbon.HIToolbox

struct HotkeyRecorder: NSViewRepresentable {
    @Binding var keyCode: Int?
    @Binding var modifiers: CGEventFlags

    func makeNSView(context: Context) -> HotkeyRecorderNSView {
        let view = HotkeyRecorderNSView()
        view.onKeyCaptured = { code, flags in
            keyCode = code
            modifiers = flags
        }
        return view
    }

    func updateNSView(_ nsView: HotkeyRecorderNSView, context: Context) {
        nsView.updateDisplay(keyCode: keyCode, modifiers: modifiers)
    }
}

final class HotkeyRecorderNSView: NSView {
    var onKeyCaptured: ((Int, CGEventFlags) -> Void)?
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

    private func setupTextField() {
        textField.isEditable = false
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel
        textField.alignment = .center
        textField.placeholderString = "Click to record shortcut"
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

        onKeyCaptured?(keyCode, flags)
        stopRecording()
    }

    func updateDisplay(keyCode: Int?, modifiers: CGEventFlags) {
        guard !isRecording else { return }
        if let keyCode {
            let modStr = KeyCodeMap.modifierSymbols(for: modifiers)
            let keyStr = KeyCodeMap.name(for: keyCode)
            textField.stringValue = "\(modStr)\(keyStr)"
        } else {
            textField.stringValue = ""
        }
    }
}
