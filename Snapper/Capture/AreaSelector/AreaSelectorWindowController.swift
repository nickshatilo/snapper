import AppKit

final class AreaSelectorWindowController {
    private var overlayWindows: [NSWindow] = []
    private var overlayViews: [AreaSelectorOverlayView] = []
    private let completion: (CGRect?) -> Void

    init(completion: @escaping (CGRect?) -> Void) {
        self.completion = completion
    }

    func show(freezeScreen: Bool) {
        for screen in NSScreen.screens {
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
            window.ignoresMouseEvents = false
            window.acceptsMouseMovedEvents = true
            window.hasShadow = false

            let overlayView = AreaSelectorOverlayView(frame: screen.frame)
            overlayView.onSelectionComplete = { [weak self] rect in
                guard let self else { return }
                // Convert from view coordinates to screen coordinates
                let screenRect = CGRect(
                    x: screen.frame.origin.x + rect.origin.x,
                    y: screen.frame.origin.y + rect.origin.y,
                    width: rect.width,
                    height: rect.height
                )
                self.completion(screenRect)
            }
            overlayView.onCancel = { [weak self] in
                self?.completion(nil)
            }

            window.contentView = overlayView
            window.makeKeyAndOrderFront(nil)
            overlayWindows.append(window)
            overlayViews.append(overlayView)
        }

        NSCursor.crosshair.push()
    }

    func close() {
        NSCursor.pop()
        for window in overlayWindows {
            window.orderOut(nil)
        }
        overlayWindows.removeAll()
        overlayViews.removeAll()
    }
}
