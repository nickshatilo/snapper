import AppKit
import SwiftUI

final class HistoryBrowserWindow {
    private var window: NSWindow?
    private let historyManager: HistoryManager

    init(historyManager: HistoryManager) {
        self.historyManager = historyManager
    }

    func show() {
        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = HistoryBrowserView(historyManager: historyManager)
        let hostingController = NSHostingController(rootView: view)

        let newWindow = NSWindow(contentViewController: hostingController)
        newWindow.title = "Capture History"
        newWindow.setContentSize(NSSize(width: 800, height: 600))
        newWindow.minSize = NSSize(width: 600, height: 400)
        newWindow.center()
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = newWindow
    }
}
