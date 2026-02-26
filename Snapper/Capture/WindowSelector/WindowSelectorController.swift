import AppKit
import ScreenCaptureKit

struct WindowInfo {
    let window: SCWindow
    let frame: CGRect
    let title: String?
    let appName: String?
}

final class WindowSelectorController {
    private var overlayWindow: NSWindow?
    private var highlightOverlay: WindowHighlightOverlay?
    private var windows: [SCWindow] = []
    private let completion: (WindowInfo?) -> Void
    private var mouseMonitor: Any?

    init(completion: @escaping (WindowInfo?) -> Void) {
        self.completion = completion
    }

    func show() {
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                self.windows = content.windows.filter { $0.frame.width > 50 && $0.frame.height > 50 }
                await MainActor.run { setupOverlay() }
            } catch {
                print("Failed to get windows: \(error)")
                completion(nil)
            }
        }
    }

    @MainActor
    private func setupOverlay() {
        guard let screen = NSScreen.main else { return }

        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.level = .init(rawValue: Int(CGWindowLevelForKey(.maximumWindow)) - 1)
        window.isOpaque = false
        window.backgroundColor = NSColor.black.withAlphaComponent(0.01)
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true

        let overlay = WindowHighlightOverlay(frame: screen.frame)
        window.contentView = overlay
        window.makeKeyAndOrderFront(nil)
        overlayWindow = window
        highlightOverlay = overlay

        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .keyDown]) { [weak self] event in
            self?.handleEvent(event)
            return event
        }
    }

    private func handleEvent(_ event: NSEvent) {
        switch event.type {
        case .mouseMoved:
            let mouseLocation = NSEvent.mouseLocation
            if let hoveredWindow = hitTestWindow(at: mouseLocation) {
                highlightOverlay?.highlightFrame = hoveredWindow.frame
                highlightOverlay?.needsDisplay = true
            } else {
                highlightOverlay?.highlightFrame = nil
                highlightOverlay?.needsDisplay = true
            }

        case .leftMouseDown:
            let mouseLocation = NSEvent.mouseLocation
            if let selectedWindow = hitTestWindow(at: mouseLocation) {
                let info = WindowInfo(
                    window: selectedWindow,
                    frame: selectedWindow.frame,
                    title: selectedWindow.title,
                    appName: selectedWindow.owningApplication?.applicationName
                )
                completion(info)
            } else {
                completion(nil)
            }

        case .keyDown:
            if event.keyCode == 53 { // Escape
                completion(nil)
            }

        default:
            break
        }
    }

    private func hitTestWindow(at point: NSPoint) -> SCWindow? {
        // Sort by z-order (windows array is already in front-to-back order)
        for window in windows {
            let frame = window.frame
            if frame.contains(point) {
                return window
            }
        }
        return nil
    }

    func close() {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
        highlightOverlay = nil
    }
}
