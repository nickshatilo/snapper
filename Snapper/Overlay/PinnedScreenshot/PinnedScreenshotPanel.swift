import AppKit

final class PinnedScreenshotPanel: NSPanel {
    var isLocked = false {
        didSet { applyLockedState() }
    }
    var currentOpacity: CGFloat = 1.0 {
        didSet {
            alphaValue = currentOpacity
            onStateChange?()
        }
    }
    let imageID: UUID
    let sourceImage: CGImage
    let sourceScale: CGFloat
    /// Called when the pin's frame or opacity changes, so it can be persisted.
    var onStateChange: (() -> Void)?
    private var geometryObservers: [NSObjectProtocol] = []

    deinit {
        for observer in geometryObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    init(image: CGImage, scale: CGFloat = 1, frame: NSRect, id: UUID = UUID()) {
        self.imageID = id
        self.sourceImage = image
        self.sourceScale = scale
        super.init(
            contentRect: frame,
            styleMask: [.nonactivatingPanel, .resizable, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )

        self.level = .floating
        self.isFloatingPanel = true
        self.hidesOnDeactivate = false
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.isMovableByWindowBackground = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.hasShadow = true
        self.minSize = NSSize(width: 100, height: 100)

        let pointScale = max(1, scale)
        let nsImage = NSImage(
            cgImage: image,
            size: NSSize(
                width: CGFloat(image.width) / pointScale,
                height: CGFloat(image.height) / pointScale
            )
        )
        let imageView = NSImageView(image: nsImage)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.autoresizingMask = [.width, .height]
        imageView.frame = NSRect(origin: .zero, size: frame.size)
        contentView = imageView

        // Drags, arrow-key nudges and resizes all end up here.
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            geometryObservers.append(
                NotificationCenter.default.addObserver(forName: name, object: self, queue: .main) { [weak self] _ in
                    self?.onStateChange?()
                }
            )
        }
    }

    /// Default on-screen size for a new pin: half the capture's point size,
    /// scaled down uniformly to fit 400×300 so the aspect ratio is kept.
    static func defaultSize(forPixelWidth width: Int, pixelHeight height: Int, scale: CGFloat) -> NSSize {
        let pointScale = max(1, scale)
        let halfWidth = CGFloat(width) / pointScale / 2
        let halfHeight = CGFloat(height) / pointScale / 2
        guard halfWidth > 0, halfHeight > 0 else { return NSSize(width: 100, height: 100) }
        let factor = min(1, 400 / halfWidth, 300 / halfHeight)
        return NSSize(width: halfWidth * factor, height: halfHeight * factor)
    }

    override var canBecomeKey: Bool { !isLocked }
    override var canBecomeMain: Bool { false }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY * 0.01
        currentOpacity = max(0.1, min(1.0, currentOpacity + delta))
    }

    override func keyDown(with event: NSEvent) {
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        switch event.keyCode {
        case 123: // Left arrow
            setFrameOrigin(NSPoint(x: frame.origin.x - step, y: frame.origin.y))
        case 124: // Right arrow
            setFrameOrigin(NSPoint(x: frame.origin.x + step, y: frame.origin.y))
        case 125: // Down arrow
            setFrameOrigin(NSPoint(x: frame.origin.x, y: frame.origin.y - step))
        case 126: // Up arrow
            setFrameOrigin(NSPoint(x: frame.origin.x, y: frame.origin.y + step))
        default:
            super.keyDown(with: event)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(withTitle: "Copy", action: #selector(copyImage), keyEquivalent: "c")
        menu.addItem(withTitle: "Save As...", action: #selector(saveImage), keyEquivalent: "s")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Annotate", action: #selector(annotateImage), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: isLocked ? "Unlock" : "Lock", action: #selector(toggleLock), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Close", action: #selector(closePanel), keyEquivalent: "w")

        for item in menu.items {
            item.target = self
        }

        NSMenu.popUpContextMenu(menu, with: event, for: contentView!)
    }

    @objc private func copyImage() {
        PasteboardHelper.copyImage(
            sourceImage,
            scale: sourceScale,
            showsConfirmation: true,
            confirmationScreen: screen
        )
    }

    @objc private func saveImage() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.nameFieldStringValue = "Pinned Screenshot.png"
        guard savePanel.runModal() == .OK, let url = savePanel.url else { return }
        // Write the captured pixels with their scale rather than re-encoding
        // the view's image, which drops the DPI and saves a retina pin at 2x.
        guard !ImageUtils.save(sourceImage, to: url, format: .png, scale: sourceScale) else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Save Failed"
        alert.informativeText = "Couldn't save the image to \(url.path)."
        alert.runModal()
    }

    @objc private func annotateImage() {
        NotificationCenter.default.post(name: .openEditor, object: ImageWrapper(sourceImage, scale: sourceScale))
        closePanel()
    }

    @objc private func toggleLock() {
        isLocked.toggle()
        NotificationCenter.default.post(name: .pinnedLockChanged, object: imageID)
    }

    @objc private func closePanel() {
        NotificationCenter.default.post(name: .pinnedScreenshotClosed, object: imageID)
        orderOut(nil)
    }
}

extension Notification.Name {
    static let pinnedScreenshotClosed = Notification.Name("pinnedScreenshotClosed")
    static let pinnedLockChanged = Notification.Name("pinnedLockChanged")
}

private extension PinnedScreenshotPanel {
    func applyLockedState() {
        // A locked pin must still receive right-clicks so its Unlock command is
        // reachable. Lock its geometry instead of making the entire panel
        // click-through and permanently inaccessible.
        ignoresMouseEvents = false
        isMovable = !isLocked
        isMovableByWindowBackground = !isLocked
        if isLocked {
            styleMask.remove(.resizable)
        } else {
            styleMask.insert(.resizable)
        }
    }
}
