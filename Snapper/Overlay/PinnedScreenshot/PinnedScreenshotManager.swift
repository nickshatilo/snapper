import AppKit

final class PinnedScreenshotManager {
    private var panels: [UUID: PinnedScreenshotPanel] = [:]
    private let appState: AppState
    private var observerTokens: [NSObjectProtocol] = []

    init(appState: AppState) {
        self.appState = appState
        observeNotifications()
        restorePersistedState()
    }

    deinit {
        for token in observerTokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    private func observeNotifications() {
        let pinToken = NotificationCenter.default.addObserver(
            forName: .pinScreenshot,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let wrapper = notification.object as? ImageWrapper else { return }
            self?.pinImage(wrapper.image)
        }
        observerTokens.append(pinToken)

        let closeToken = NotificationCenter.default.addObserver(
            forName: .pinnedScreenshotClosed,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let id = notification.object as? UUID else { return }
            self?.panels.removeValue(forKey: id)
            self?.persistState()
        }
        observerTokens.append(closeToken)

        let opacityToken = NotificationCenter.default.addObserver(
            forName: .pinnedOpacityChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyDefaultOpacityToAllPanels()
        }
        observerTokens.append(opacityToken)
    }

    func pinImage(_ image: CGImage, frame: NSRect? = nil) {
        let defaultSize = NSSize(
            width: min(CGFloat(image.width) / 2, 400),
            height: min(CGFloat(image.height) / 2, 300)
        )
        let panelFrame = frame ?? NSRect(
            x: (NSScreen.main?.frame.midX ?? 500) - defaultSize.width / 2,
            y: (NSScreen.main?.frame.midY ?? 400) - defaultSize.height / 2,
            width: defaultSize.width,
            height: defaultSize.height
        )

        let panel = PinnedScreenshotPanel(image: image, frame: panelFrame)
        panel.currentOpacity = CGFloat(appState.defaultPinnedOpacity)
        panels[panel.imageID] = panel
        panel.makeKeyAndOrderFront(nil)
        persistState()
    }

    private func applyDefaultOpacityToAllPanels() {
        let opacity = CGFloat(appState.defaultPinnedOpacity)
        for (_, panel) in panels {
            panel.currentOpacity = opacity
        }
        persistState()
    }

    private func persistState() {
        var states: [[String: Any]] = []
        for (_, panel) in panels {
            let state: [String: Any] = [
                "x": panel.frame.origin.x,
                "y": panel.frame.origin.y,
                "width": panel.frame.width,
                "height": panel.frame.height,
                "opacity": panel.currentOpacity,
                "locked": panel.isLocked,
            ]
            states.append(state)
        }
        UserDefaults.standard.set(states, forKey: Constants.Keys.pinnedScreenshots)
    }

    private func restorePersistedState() {
        // Restore is limited since we don't persist the actual images
        // In a full implementation, we'd save image paths and reload them
    }
}
