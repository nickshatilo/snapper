import AppKit

final class PinnedScreenshotPanel: NSPanel {
    var isLocked = false {
        didSet { ignoresMouseEvents = isLocked }
    }
    var currentOpacity: CGFloat = 1.0 {
        didSet { alphaValue = currentOpacity }
    }
    let imageID: UUID

    init(image: CGImage, frame: NSRect, id: UUID = UUID()) {
        self.imageID = id
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

        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        let imageView = NSImageView(image: nsImage)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.autoresizingMask = [.width, .height]
        imageView.frame = NSRect(origin: .zero, size: frame.size)
        contentView = imageView
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
        if let imageView = contentView as? NSImageView, let image = imageView.image {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([image])
        }
    }

    @objc private func saveImage() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.nameFieldStringValue = "Pinned Screenshot.png"
        if savePanel.runModal() == .OK, let url = savePanel.url,
           let imageView = contentView as? NSImageView, let image = imageView.image,
           let tiffData = image.tiffRepresentation,
           let bitmapRep = NSBitmapImageRep(data: tiffData),
           let pngData = bitmapRep.representation(using: .png, properties: [:]) {
            try? pngData.write(to: url)
        }
    }

    @objc private func annotateImage() {
        if let imageView = contentView as? NSImageView, let image = imageView.image,
           let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            NotificationCenter.default.post(name: .openEditor, object: ImageWrapper(cgImage))
            closePanel()
        }
    }

    @objc private func toggleLock() {
        isLocked.toggle()
    }

    @objc private func closePanel() {
        NotificationCenter.default.post(name: .pinnedScreenshotClosed, object: imageID)
        orderOut(nil)
    }
}

extension Notification.Name {
    static let pinnedScreenshotClosed = Notification.Name("pinnedScreenshotClosed")
}
