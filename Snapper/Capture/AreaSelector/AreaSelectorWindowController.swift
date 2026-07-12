import AppKit

struct AreaSelectionResult {
    let rect: CGRect
    let frozenImage: CGImage?
}

struct FrozenScreenSnapshot {
    struct Display {
        let frame: CGRect
        let image: CGImage

        var scaleX: CGFloat { CGFloat(image.width) / frame.width }
        var scaleY: CGFloat { CGFloat(image.height) / frame.height }
    }

    let displays: [Display]

    func image(for rect: CGRect, retinaScale: Bool) -> CGImage? {
        let intersecting = displays.filter { $0.frame.intersects(rect) }
        guard !intersecting.isEmpty, rect.width > 0, rect.height > 0 else { return nil }

        let outputScale = retinaScale
            ? max(1, intersecting.map { max($0.scaleX, $0.scaleY) }.max() ?? 1)
            : 1
        let outputWidth = max(1, Int((rect.width * outputScale).rounded(.up)))
        let outputHeight = max(1, Int((rect.height * outputScale).rounded(.up)))

        guard let context = CGContext(
            data: nil,
            width: outputWidth,
            height: outputHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .high
        // Draw using top-left coordinates, matching CGImage.cropping(to:).
        context.translateBy(x: 0, y: CGFloat(outputHeight))
        context.scaleBy(x: 1, y: -1)

        for display in intersecting {
            let intersection = display.frame.intersection(rect)
            guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else { continue }

            let sourceRect = CGRect(
                x: (intersection.minX - display.frame.minX) * display.scaleX,
                y: (display.frame.maxY - intersection.maxY) * display.scaleY,
                width: intersection.width * display.scaleX,
                height: intersection.height * display.scaleY
            ).integral
            guard let cropped = display.image.cropping(to: sourceRect) else { continue }

            let destinationRect = CGRect(
                x: (intersection.minX - rect.minX) * outputScale,
                y: (rect.maxY - intersection.maxY) * outputScale,
                width: intersection.width * outputScale,
                height: intersection.height * outputScale
            ).integral
            context.draw(cropped, in: destinationRect)
        }

        return context.makeImage()
    }
}

final class AreaSelectorWindowController {
    private var overlayWindows: [NSWindow] = []
    private var overlayViews: [AreaSelectorOverlayView] = []
    private var overlayScreenFrames: [ObjectIdentifier: CGRect] = [:]
    private var overlayScreenScales: [ObjectIdentifier: CGFloat] = [:]
    private var localKeyMonitor: Any?
    private var localMouseMonitor: Any?
    private var didFinish = false
    private var selectionStartInScreen: NSPoint?
    private var selectionCurrentInScreen: NSPoint?
    private let completion: (AreaSelectionResult?) -> Void
    private var frozenSnapshot: FrozenScreenSnapshot?
    private var retinaScale = true

    init(completion: @escaping (AreaSelectionResult?) -> Void) {
        self.completion = completion
    }

    func show(freezeScreen: Bool, showMagnifier: Bool = false, retinaScale: Bool = true) {
        didFinish = false
        self.retinaScale = retinaScale
        frozenSnapshot = freezeScreen ? captureSnapshot() : nil
        installKeyMonitor()
        // Delay activation until the current event cycle finishes (for menu-triggered captures).
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.didFinish else { return }
            NSApp.activate(ignoringOtherApps: true)
        }

        for screen in NSScreen.screens {
            let window = AreaSelectorWindow(
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
            // We manage the window lifetime via `overlayWindows`; avoid legacy release-on-close over-release.
            window.isReleasedWhenClosed = false

            let overlayView = AreaSelectorOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
            overlayView.showsMagnifier = showMagnifier
            overlayView.frozenImage = frozenSnapshot?.displays.first(where: { $0.frame == screen.frame })?.image
            let overlayID = ObjectIdentifier(overlayView)
            overlayScreenFrames[overlayID] = screen.frame
            overlayScreenScales[overlayID] = max(1.0, screen.backingScaleFactor)

            window.contentView = overlayView
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(overlayView)
            overlayWindows.append(window)
            overlayViews.append(overlayView)
        }

        installMouseMonitor()
    }

    func close() {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        for window in overlayWindows {
            window.close()
        }
        overlayWindows.removeAll()
        overlayViews.removeAll()
        overlayScreenFrames.removeAll()
        overlayScreenScales.removeAll()
        selectionStartInScreen = nil
        selectionCurrentInScreen = nil
        frozenSnapshot = nil
    }

    private func installKeyMonitor() {
        guard localKeyMonitor == nil else { return }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { // Escape
                let discardedAnySelection = self.overlayViews.reduce(false) { partialResult, overlayView in
                    overlayView.clearSelection() || partialResult
                }
                self.selectionStartInScreen = nil
                self.selectionCurrentInScreen = nil
                if !discardedAnySelection {
                    self.finish(with: nil)
                }
                return nil
            }
            return event
        }
    }

    private func installMouseMonitor() {
        guard localMouseMonitor == nil else { return }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .mouseMoved]
        ) { [weak self] event in
            guard let self else { return event }
            if self.handleMouseEvent(event) {
                return nil
            }
            return event
        }
    }

    private func handleMouseEvent(_ event: NSEvent) -> Bool {
        guard isOverlayEvent(event) else { return false }
        let screenPoint = screenPoint(for: event)

        switch event.type {
        case .leftMouseDown:
            selectionStartInScreen = screenPoint
            selectionCurrentInScreen = screenPoint
            updateSelectionAcrossOverlays()
            updateMagnifierAcrossOverlays(at: screenPoint)
            return true
        case .leftMouseDragged:
            guard selectionStartInScreen != nil else { return true }
            selectionCurrentInScreen = screenPoint
            updateSelectionAcrossOverlays()
            updateMagnifierAcrossOverlays(at: screenPoint)
            return true
        case .leftMouseUp:
            guard let start = selectionStartInScreen else { return true }
            let end = selectionCurrentInScreen ?? screenPoint
            let selectedRect = normalizedRect(from: start, to: end)
            selectionStartInScreen = nil
            selectionCurrentInScreen = nil
            clearSelectionAcrossOverlays()

            if selectedRect.width > 5, selectedRect.height > 5 {
                let frozenImage = frozenSnapshot?.image(for: selectedRect, retinaScale: retinaScale)
                finish(with: AreaSelectionResult(rect: selectedRect, frozenImage: frozenImage))
            }
            return true
        case .mouseMoved:
            updateMagnifierAcrossOverlays(at: screenPoint)
            return true
        default:
            return false
        }
    }

    private func isOverlayEvent(_ event: NSEvent) -> Bool {
        guard let window = event.window else { return false }
        return overlayWindows.contains { $0 === window }
    }

    private func screenPoint(for event: NSEvent) -> NSPoint {
        if let window = event.window {
            return window.convertPoint(toScreen: event.locationInWindow)
        }
        return NSEvent.mouseLocation
    }

    private func updateSelectionAcrossOverlays() {
        guard let start = selectionStartInScreen, let current = selectionCurrentInScreen else {
            clearSelectionAcrossOverlays()
            return
        }
        let globalRect = normalizedRect(from: start, to: current)
        let globalScale = max(1.0, overlayViews.compactMap { overlayView in
            let overlayID = ObjectIdentifier(overlayView)
            guard let screenFrame = overlayScreenFrames[overlayID],
                  screenFrame.intersects(globalRect),
                  let screenScale = overlayScreenScales[overlayID] else {
                return nil
            }
            return screenScale
        }.max() ?? 1.0)
        let pixelSize = CGSize(
            width: globalRect.width * globalScale,
            height: globalRect.height * globalScale
        )

        for overlayView in overlayViews {
            guard let screenFrame = overlayScreenFrames[ObjectIdentifier(overlayView)] else { continue }
            let localRect = CGRect(
                x: globalRect.minX - screenFrame.minX,
                y: globalRect.minY - screenFrame.minY,
                width: globalRect.width,
                height: globalRect.height
            ).intersection(overlayView.bounds)
            overlayView.setSelectionRect(localRect.isNull ? nil : localRect, pixelSize: pixelSize)
        }
    }

    private func clearSelectionAcrossOverlays() {
        for overlayView in overlayViews {
            overlayView.setSelectionRect(nil, pixelSize: nil)
        }
    }

    private func updateMagnifierAcrossOverlays(at screenPoint: NSPoint) {
        for overlayView in overlayViews {
            guard let screenFrame = overlayScreenFrames[ObjectIdentifier(overlayView)] else { continue }
            overlayView.setMagnifierPointInScreen(screenFrame.contains(screenPoint) ? screenPoint : nil)
        }
    }

    private func normalizedRect(from first: NSPoint, to second: NSPoint) -> CGRect {
        CGRect(
            x: min(first.x, second.x),
            y: min(first.y, second.y),
            width: abs(second.x - first.x),
            height: abs(second.y - first.y)
        )
    }

    private func finish(with result: AreaSelectionResult?) {
        guard !didFinish else { return }
        didFinish = true
        // Avoid tearing down windows while AppKit is still dispatching the current mouse/key event.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.close()
            self.completion(result)
        }
    }

    private func captureSnapshot() -> FrozenScreenSnapshot? {
        let displays = NSScreen.screens.compactMap { screen -> FrozenScreenSnapshot.Display? in
            guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                  let image = CGDisplayCreateImage(displayID) else {
                return nil
            }
            return FrozenScreenSnapshot.Display(frame: screen.frame, image: image)
        }
        return displays.isEmpty ? nil : FrozenScreenSnapshot(displays: displays)
    }
}

private final class AreaSelectorWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
