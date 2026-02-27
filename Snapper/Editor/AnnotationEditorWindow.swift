import AppKit
import SwiftUI

final class AnnotationEditorWindow: NSObject, NSWindowDelegate {
    private static var activeWindows: [UUID: AnnotationEditorWindow] = [:]

    private let id = UUID()
    private let window: NSWindow

    private init(image: CGImage) {
        let canvasState = CanvasState(image: image)
        let toolManager = ToolManager()
        let view = AnnotationEditorView(canvasState: canvasState, toolManager: toolManager)
        let hostingController = NSHostingController(rootView: view)

        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let maxWindowWidth = min(visibleFrame.width * 0.86, 1400)
        let maxWindowHeight = min(visibleFrame.height * 0.86, 960)
        let chromeWidth: CGFloat = 80
        let chromeHeight: CGFloat = 120
        let targetWidth = min(CGFloat(image.width), maxWindowWidth - chromeWidth) + chromeWidth
        let targetHeight = min(CGFloat(image.height), maxWindowHeight - chromeHeight) + chromeHeight

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Annotation Editor"
        window.setContentSize(NSSize(width: max(720, targetWidth), height: max(520, targetHeight)))
        window.minSize = NSSize(width: 600, height: 400)
        window.center()
        self.window = window
        super.init()
        self.window.delegate = self
    }

    static func open(with image: CGImage) {
        let editorWindow = AnnotationEditorWindow(image: image)
        activeWindows[editorWindow.id] = editorWindow
        editorWindow.window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        Self.activeWindows.removeValue(forKey: id)
    }
}
