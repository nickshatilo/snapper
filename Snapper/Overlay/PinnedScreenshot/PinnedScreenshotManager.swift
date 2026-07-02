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
            self?.pinImage(wrapper.image, scale: wrapper.scale)
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

    func pinImage(
        _ image: CGImage,
        scale: CGFloat = 1,
        frame: NSRect? = nil,
        id: UUID = UUID(),
        opacity: CGFloat? = nil,
        locked: Bool = false,
        persist: Bool = true
    ) {
        let pointScale = max(1, scale)
        let defaultSize = NSSize(
            width: min(CGFloat(image.width) / pointScale / 2, 400),
            height: min(CGFloat(image.height) / pointScale / 2, 300)
        )
        let panelFrame = frame ?? NSRect(
            x: (NSScreen.main?.frame.midX ?? 500) - defaultSize.width / 2,
            y: (NSScreen.main?.frame.midY ?? 400) - defaultSize.height / 2,
            width: defaultSize.width,
            height: defaultSize.height
        )

        let panel = PinnedScreenshotPanel(image: image, scale: pointScale, frame: panelFrame, id: id)
        panel.currentOpacity = opacity ?? CGFloat(appState.defaultPinnedOpacity)
        panel.isLocked = locked
        panels[panel.imageID] = panel
        panel.makeKeyAndOrderFront(nil)
        if persist {
            persistState()
        }
    }

    private func applyDefaultOpacityToAllPanels() {
        let opacity = CGFloat(appState.defaultPinnedOpacity)
        for (_, panel) in panels {
            panel.currentOpacity = opacity
        }
        persistState()
    }

    private var pinsDirectory: URL? {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return nil }
        let directory = appSupport.appendingPathComponent("Snapper/Pins", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func persistState() {
        var states: [[String: Any]] = []
        for (id, panel) in panels {
            if let directory = pinsDirectory {
                let imageURL = directory.appendingPathComponent("\(id.uuidString).png")
                if !FileManager.default.fileExists(atPath: imageURL.path) {
                    _ = ImageUtils.save(panel.sourceImage, to: imageURL, format: .png)
                }
            }
            let state: [String: Any] = [
                "id": id.uuidString,
                "x": panel.frame.origin.x,
                "y": panel.frame.origin.y,
                "width": panel.frame.width,
                "height": panel.frame.height,
                "opacity": panel.currentOpacity,
                "locked": panel.isLocked,
                "scale": panel.sourceScale,
            ]
            states.append(state)
        }
        UserDefaults.standard.set(states, forKey: Constants.Keys.pinnedScreenshots)
        removeOrphanedPinImages(keeping: Set(panels.keys))
    }

    private func removeOrphanedPinImages(keeping ids: Set<UUID>) {
        guard let directory = pinsDirectory,
              let files = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
              ) else { return }
        for file in files where file.pathExtension == "png" {
            guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent),
                  !ids.contains(id) else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func restorePersistedState() {
        guard let states = UserDefaults.standard.array(
            forKey: Constants.Keys.pinnedScreenshots
        ) as? [[String: Any]],
        let directory = pinsDirectory else { return }

        for state in states {
            guard let idString = state["id"] as? String,
                  let id = UUID(uuidString: idString),
                  let x = (state["x"] as? NSNumber)?.doubleValue,
                  let y = (state["y"] as? NSNumber)?.doubleValue,
                  let width = (state["width"] as? NSNumber)?.doubleValue,
                  let height = (state["height"] as? NSNumber)?.doubleValue else { continue }

            let imageURL = directory.appendingPathComponent("\(id.uuidString).png")
            guard let nsImage = NSImage(contentsOf: imageURL),
                  let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                continue
            }

            // Defer persistence until every pin is restored — persisting per pin
            // would run orphan cleanup with only the pins restored so far in
            // `panels`, deleting the image files of pins not yet restored.
            pinImage(
                cgImage,
                scale: (state["scale"] as? NSNumber).map { CGFloat($0.doubleValue) } ?? 1,
                frame: NSRect(x: x, y: y, width: width, height: height),
                id: id,
                opacity: (state["opacity"] as? NSNumber).map { CGFloat($0.doubleValue) },
                locked: (state["locked"] as? NSNumber)?.boolValue ?? false,
                persist: false
            )
        }

        // Persist once now that all panels exist, reconciling UserDefaults and
        // pruning image files for any pins that failed to restore.
        persistState()
    }
}
