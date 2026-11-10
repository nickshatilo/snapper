import AppKit
import Observation
import SwiftUI

final class AnnotationEditorWindow: NSObject, NSWindowDelegate {
    private static var activeWindows: [UUID: AnnotationEditorWindow] = [:]

    /// Supplies the user's current save settings (folder, format, quality)
    /// for ⌘S and the save-on-close prompt. Installed at launch; without it
    /// saves fall back to `CaptureOptions()` defaults.
    static var saveOptionsProvider: (() -> CaptureOptions)?

    private let id = UUID()
    private let window: NSWindow
    private let canvasState: CanvasState

    private init(image: CGImage, scale: CGFloat) {
        let canvasState = CanvasState(image: image, scale: scale)
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
        // A Swift strong reference plus the AppKit default (release on close)
        // double-releases the window during close.
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: max(720, targetWidth), height: max(520, targetHeight)))
        window.minSize = NSSize(width: 600, height: 400)
        window.center()
        self.window = window
        self.canvasState = canvasState
        super.init()
        self.window.delegate = self
        trackDocumentEdited()
    }

    /// `scale` is the backing scale of the display the image was captured
    /// from; exports from the editor carry it.
    static func open(with image: CGImage, scale: CGFloat = 1) {
        let editorWindow = AnnotationEditorWindow(image: image, scale: scale)
        activeWindows[editorWindow.id] = editorWindow
        editorWindow.window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Runs the unsaved-changes prompt for every open editor before the app
    /// quits (quitting closes windows without asking their delegates).
    /// Returns false if the user cancelled, in which case the quit is off.
    static func closeAllForTermination() -> Bool {
        for editor in Array(activeWindows.values) {
            if editor.canvasState.hasUnsavedChanges {
                editor.window.makeKeyAndOrderFront(nil)
            }
            guard editor.windowShouldClose(editor.window) else { return false }
            editor.window.close()
        }
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // An in-progress inline text edit only reaches the undo history once
        // committed; without this, closing mid-edit would discard it unasked.
        canvasState.commitPendingEdits()
        guard canvasState.hasUnsavedChanges else { return true }

        let alert = NSAlert()
        alert.messageText = "Do you want to save the changes to this screenshot?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        // Order matters: the first button is the default (Return) and AppKit
        // binds Escape to the button titled "Cancel".
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Don't Save")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            // Stay open if the save failed so the work isn't lost.
            return EditorExporter.save(
                canvasState,
                options: Self.saveOptionsProvider?() ?? CaptureOptions()
            )
        case .alertThirdButtonReturn:
            return true
        default:
            return false
        }
    }

    func windowWillClose(_ notification: Notification) {
        Self.activeWindows.removeValue(forKey: id)
    }

    /// Mirrors unsaved changes in the close button's dot, re-arming itself
    /// each time the tracked state changes.
    private func trackDocumentEdited() {
        window.isDocumentEdited = withObservationTracking {
            canvasState.hasUnsavedChanges
        } onChange: { [weak self] in
            // Observation fires before the new value is stored; read it on
            // the next main-actor turn.
            Task { @MainActor [weak self] in
                self?.trackDocumentEdited()
            }
        }
    }
}
