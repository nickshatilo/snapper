import AppKit
import SwiftUI

final class AllInOneHUDPanel {
    private var panel: AllInOneHUDNSPanel?
    private var observerToken: NSObjectProtocol?

    init() {
        observerToken = NotificationCenter.default.addObserver(
            forName: .showAllInOneHUD,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.show()
        }
    }

    deinit {
        if let observerToken {
            NotificationCenter.default.removeObserver(observerToken)
        }
    }

    func show() {
        if panel != nil {
            // The HUD hotkey/menu item toggles: a second press dismisses it.
            dismiss()
            return
        }

        // Show on the screen the user is working on (mouse location), not the
        // menu-bar screen.
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main
        guard let screen else { return }

        let view = AllInOneHUDView { [weak self] in
            self?.dismiss()
        }
        let hostingView = NSHostingView(rootView: view)

        let panelWidth: CGFloat = 480
        let panelHeight: CGFloat = 80
        let panelX = screen.frame.midX - panelWidth / 2
        let panelY = screen.visibleFrame.minY + 40

        let newPanel = AllInOneHUDNSPanel(
            contentRect: NSRect(x: panelX, y: panelY, width: panelWidth, height: panelHeight),
            // No .closable: a traffic-light button would overlap the first mode
            // button. Dismiss with Escape or by toggling the HUD hotkey/menu item.
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        newPanel.isReleasedWhenClosed = false
        // Escape (and any close) routes through dismiss() so `panel` never
        // points at a closed window.
        newPanel.onCancel = { [weak self] in
            self?.dismiss()
        }
        newPanel.level = .floating
        newPanel.isFloatingPanel = true
        newPanel.hidesOnDeactivate = false
        newPanel.titlebarAppearsTransparent = true
        newPanel.titleVisibility = .hidden
        newPanel.isMovableByWindowBackground = true
        newPanel.isOpaque = false
        newPanel.backgroundColor = .clear
        newPanel.contentView = hostingView

        newPanel.makeKeyAndOrderFront(nil)
        panel = newPanel
    }

    private func dismiss() {
        guard let panel else { return }
        self.panel = nil
        panel.onCancel = nil
        panel.orderOut(nil)
    }
}

private final class AllInOneHUDNSPanel: NSPanel {
    var onCancel: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func performClose(_ sender: Any?) {
        onCancel?()
    }

    override func close() {
        // Hand off to the owner so it drops its reference.
        if let onCancel {
            onCancel()
        } else {
            super.close()
        }
    }
}
