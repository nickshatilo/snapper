import AppKit
import SwiftUI

final class AllInOneHUDPanel {
    private var panel: NSPanel?

    init() {
        NotificationCenter.default.addObserver(
            forName: .showAllInOneHUD,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.show()
        }
    }

    func show() {
        if let existing = panel {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        guard let screen = NSScreen.main else { return }

        let view = AllInOneHUDView { [weak self] in
            self?.dismiss()
        }
        let hostingView = NSHostingView(rootView: view)

        let panelWidth: CGFloat = 480
        let panelHeight: CGFloat = 80
        let panelX = screen.frame.midX - panelWidth / 2
        let panelY = screen.visibleFrame.minY + 40

        let newPanel = NSPanel(
            contentRect: NSRect(x: panelX, y: panelY, width: panelWidth, height: panelHeight),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
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
        panel?.orderOut(nil)
        panel = nil
    }
}
