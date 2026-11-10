import AppKit
import ScreenCaptureKit

/// All rects and points passed to this service are CG top-left global
/// coordinates (the native space of ScreenCaptureKit's `SCDisplay.frame`,
/// `SCWindow.frame`, and `SCStreamConfiguration.sourceRect`). Callers holding
/// AppKit screen rects must convert via `CoordinateSpace.appKitToCG` first.
final class ScreenCaptureService {
    struct MultiDisplayCapture {
        let image: CGImage
        let sourceRect: CGRect
        let scale: CGFloat
    }

    struct DisplayCapture {
        let frame: CGRect
        let scale: CGFloat
        let image: CGImage
    }

    struct RectCaptureContext {
        let displayFrame: CGRect
        let displayScale: CGFloat
        let filter: SCContentFilter
        let configuration: SCStreamConfiguration
    }

    /// One display's contents at its native pixel density.
    struct DisplaySnapshot {
        let displayID: CGDirectDisplayID
        let image: CGImage
    }

    /// Snapper's own floating UI (Quick Access overlay, pins, HUDs, the timer
    /// countdown, selection overlays) sits above the normal window level and
    /// must never end up in a screenshot. Its regular windows (editor,
    /// settings, history) are layer 0 and stay capturable like any other app's.
    static func isOwnOverlayWindow(ownerPID: pid_t?, layer: Int, ownPID: pid_t) -> Bool {
        ownerPID == ownPID && layer > 0
    }

    private func ownOverlayWindows(in content: SCShareableContent) -> [SCWindow] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return content.windows.filter {
            Self.isOwnOverlayWindow(
                ownerPID: $0.owningApplication?.processID,
                layer: $0.windowLayer,
                ownPID: ownPID
            )
        }
    }

    /// Always fetched fresh: the window list decides which overlays get
    /// excluded, and a stale one would miss a panel that appeared since.
    private func fetchShareableContent() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }

    /// Captures every display separately at its native scale, e.g. as the
    /// frozen backdrop for area selection.
    func captureDisplaySnapshots() async throws -> [DisplaySnapshot] {
        try ensureScreenCapturePermission()
        let content = try await fetchShareableContent()
        guard !content.displays.isEmpty else {
            throw CaptureError.noDisplay
        }

        let excludedWindows = ownOverlayWindows(in: content)
        var snapshots: [DisplaySnapshot] = []
        snapshots.reserveCapacity(content.displays.count)

        for display in content.displays {
            let scale = displayScaleFactor(for: display)
            let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
            let config = SCStreamConfiguration()
            config.width = max(1, Int(CGFloat(display.width) * scale))
            config.height = max(1, Int(CGFloat(display.height) * scale))
            config.showsCursor = false
            config.captureResolution = .best

            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
            snapshots.append(DisplaySnapshot(displayID: display.displayID, image: image))
        }

        return snapshots
    }

    func captureAllDisplays(retinaScale: Bool = true) async throws -> MultiDisplayCapture {
        try ensureScreenCapturePermission()
        let content = try await fetchShareableContent()
        return try await captureAllDisplays(in: content, retinaScale: retinaScale)
    }

    struct WindowCapture {
        let image: CGImage
        /// Pixels per point of `image`.
        let scale: CGFloat
    }

    func captureWindow(_ window: SCWindow, retinaScale: Bool = true, includeShadow: Bool = true) async throws -> WindowCapture {
        try ensureScreenCapturePermission()
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        // With shadows, the captured content is larger than the window frame;
        // sizing the output to the frame would squeeze window + shadow into it.
        // `filter.contentRect` covers the full content (points), and
        // `pointPixelScale` is the native pixel density for it.
        let filterScale = CGFloat(filter.pointPixelScale)
        let nativeScale: CGFloat
        if filterScale > 0 {
            nativeScale = filterScale
        } else {
            let content = try await fetchShareableContent()
            nativeScale = displayScale(for: window.frame, in: content)
        }
        let scale = retinaScale ? nativeScale : 1.0
        let contentSize = includeShadow && !filter.contentRect.isEmpty
            ? filter.contentRect.size
            : window.frame.size
        config.width = max(1, Int((contentSize.width * scale).rounded()))
        config.height = max(1, Int((contentSize.height * scale).rounded()))
        config.showsCursor = false
        config.captureResolution = .best
        config.shouldBeOpaque = false
        config.ignoreShadowsSingleWindow = !includeShadow

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )
        return WindowCapture(image: image, scale: scale)
    }

    func captureRect(_ rect: CGRect, retinaScale: Bool = true) async throws -> CGImage {
        try ensureScreenCapturePermission()
        let content = try await fetchShareableContent()
        let intersectingDisplays = content.displays.filter {
            displayRect($0).intersects(rect)
        }

        if intersectingDisplays.count > 1 {
            let multiDisplay = try await captureAllDisplays(in: content, retinaScale: retinaScale)
            return try crop(rect: rect, from: multiDisplay.image, sourceRect: multiDisplay.sourceRect, scale: multiDisplay.scale)
        }

        let context = try await prepareRectCapture(for: rect, content: content, retinaScale: retinaScale)
        return try await captureRect(rect, using: context)
    }

    func prepareRectCapture(
        for rect: CGRect,
        content: SCShareableContent? = nil,
        retinaScale: Bool = true
    ) async throws -> RectCaptureContext {
        try ensureScreenCapturePermission()
        let resolvedContent: SCShareableContent
        if let content {
            resolvedContent = content
        } else {
            resolvedContent = try await fetchShareableContent()
        }
        guard let display = resolveDisplay(for: rect, in: resolvedContent) else {
            throw CaptureError.noDisplay
        }

        let displayFrame = CGRect(
            x: CGFloat(display.frame.origin.x),
            y: CGFloat(display.frame.origin.y),
            width: CGFloat(display.frame.width),
            height: CGFloat(display.frame.height)
        )

        let scale = retinaScale ? displayScaleFactor(for: display) : 1.0
        let filter = SCContentFilter(
            display: display,
            excludingWindows: ownOverlayWindows(in: resolvedContent)
        )
        let config = SCStreamConfiguration()
        config.showsCursor = false
        config.captureResolution = .best
        config.width = max(1, Int(CGFloat(display.width) * scale))
        config.height = max(1, Int(CGFloat(display.height) * scale))

        return RectCaptureContext(
            displayFrame: displayFrame,
            displayScale: scale,
            filter: filter,
            configuration: config
        )
    }

    func captureRect(_ rect: CGRect, using context: RectCaptureContext) async throws -> CGImage {
        try ensureScreenCapturePermission()

        let fullImage = try await SCScreenshotManager.captureImage(
            contentFilter: context.filter,
            configuration: context.configuration
        )

        return try crop(rect: rect, from: fullImage, sourceRect: context.displayFrame, scale: context.displayScale)
    }

    func getShareableContent() async throws -> SCShareableContent {
        try ensureScreenCapturePermission()
        return try await fetchShareableContent()
    }

    private func ensureScreenCapturePermission() throws {
        guard PermissionChecker.isScreenCaptureGranted() else {
            throw CaptureError.permissionDenied
        }
    }

    /// The display holding most of `rect` (by intersection area), so a rect
    /// straddling two displays resolves to where the bulk of it is rather
    /// than wherever its top-left corner happens to sit. Callers that stream
    /// a single display must still clip `rect` to the returned display.
    private func resolveDisplay(for rect: CGRect, in content: SCShareableContent) -> SCDisplay? {
        var bestDisplay: SCDisplay?
        var bestArea: CGFloat = 0
        for display in content.displays {
            let overlap = displayRect(display).intersection(rect)
            guard !overlap.isNull else { continue }
            let area = overlap.width * overlap.height
            if bestDisplay == nil || area > bestArea {
                bestDisplay = display
                bestArea = area
            }
        }
        if let bestDisplay {
            return bestDisplay
        }
        // Degenerate (zero-size) rects: fall back to the display containing the origin.
        return content.displays.first(where: { displayRect($0).contains(rect.origin) })
            ?? content.displays.first
    }

    private func captureAllDisplays(
        in content: SCShareableContent,
        retinaScale: Bool
    ) async throws -> MultiDisplayCapture {
        guard !content.displays.isEmpty else {
            throw CaptureError.noDisplay
        }

        let excludedWindows = ownOverlayWindows(in: content)
        var capturedDisplays: [DisplayCapture] = []
        capturedDisplays.reserveCapacity(content.displays.count)

        for display in content.displays {
            let frame = displayRect(display)
            let scale = retinaScale ? displayScaleFactor(for: display) : 1.0
            let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
            let config = SCStreamConfiguration()
            config.width = max(1, Int(frame.width * scale))
            config.height = max(1, Int(frame.height * scale))
            config.showsCursor = false
            config.captureResolution = .best

            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
            capturedDisplays.append(DisplayCapture(frame: frame, scale: scale, image: image))
        }

        return try Self.composeDisplays(capturedDisplays)
    }

    /// Composes ScreenCaptureKit display images into one image whose pixel
    /// coordinates use the same top-left convention as the display frames.
    /// The bitmap context itself remains in native Quartz bottom-left space so
    /// drawing a CGImage does not mirror its contents vertically.
    static func composeDisplays(_ capturedDisplays: [DisplayCapture]) throws -> MultiDisplayCapture {
        guard !capturedDisplays.isEmpty else {
            throw CaptureError.noDisplay
        }

        // Each display's scale is already 1.0 when Retina capture is off.
        let canvasScale = max(1.0, capturedDisplays.map(\.scale).max() ?? 1.0)
        guard let composed = composeDisplays(
            capturedDisplays.map { (frame: $0.frame, image: $0.image) },
            canvasScale: canvasScale
        ) else {
            throw CaptureError.cropFailed
        }

        return MultiDisplayCapture(
            image: composed.image,
            sourceRect: composed.unionRect,
            scale: canvasScale
        )
    }

    /// Composes per-display images into one canvas laid out in CG top-left
    /// global space: the result's top-left pixel is `unionRect`'s top-left,
    /// matching what `crop()` expects. Display frames are CG global points.
    static func composeDisplays(
        _ displays: [(frame: CGRect, image: CGImage)],
        canvasScale: CGFloat
    ) -> (image: CGImage, unionRect: CGRect)? {
        guard !displays.isEmpty else { return nil }
        let unionRect = displays
            .map(\.frame)
            .reduce(CGRect.null) { partial, frame in
                partial.union(frame)
            }
        let canvasWidth = max(1, Int((unionRect.width * canvasScale).rounded(.up)))
        let canvasHeight = max(1, Int((unionRect.height * canvasScale).rounded(.up)))

        guard let context = CGContext(
            data: nil,
            width: canvasWidth,
            height: canvasHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: ImageUtils.outputColorSpace(for: displays.map(\.image)),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high

        for display in displays {
            // Display frames use top-left global coordinates, while the bitmap
            // context uses bottom-left coordinates. Convert only the placement;
            // flipping the context would also mirror each captured image.
            let targetRect = CGRect(
                x: (display.frame.minX - unionRect.minX) * canvasScale,
                y: (unionRect.maxY - display.frame.maxY) * canvasScale,
                width: display.frame.width * canvasScale,
                height: display.frame.height * canvasScale
            ).integral
            context.draw(display.image, in: targetRect)
        }

        guard let image = context.makeImage() else { return nil }
        return (image, unionRect)
    }

    private func crop(rect: CGRect, from image: CGImage, sourceRect: CGRect, scale: CGFloat) throws -> CGImage {
        // Both rects are CG top-left global point-space; scale into pixel-space.
        let localRect = CGRect(
            x: (rect.minX - sourceRect.minX) * scale,
            y: (rect.minY - sourceRect.minY) * scale,
            width: rect.width * scale,
            height: rect.height * scale
        ).integral

        let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let cropRect = localRect.intersection(imageBounds)
        guard cropRect.width > 0, cropRect.height > 0,
              let croppedImage = image.cropping(to: cropRect) else {
            throw CaptureError.cropFailed
        }
        return croppedImage
    }

    private func displayRect(_ display: SCDisplay) -> CGRect {
        CGRect(
            x: CGFloat(display.frame.origin.x),
            y: CGFloat(display.frame.origin.y),
            width: CGFloat(display.frame.width),
            height: CGFloat(display.frame.height)
        )
    }

    private func displayScale(for rect: CGRect, in content: SCShareableContent) -> CGFloat {
        guard let display = resolveDisplay(for: rect, in: content) else { return 1 }
        return displayScaleFactor(for: display)
    }

    private func displayScaleFactor(for display: SCDisplay) -> CGFloat {
        // Called from background tasks, so avoid NSScreen (main-thread AppKit
        // state). The current mode's backing pixel width over its point width is
        // the display's backing scale factor.
        guard let mode = CGDisplayCopyDisplayMode(display.displayID), mode.width > 0 else {
            return 2.0
        }
        return max(1, CGFloat(mode.pixelWidth) / CGFloat(mode.width))
    }
}

enum CaptureError: Error, LocalizedError {
    case noDisplay
    case noWindow
    case cropFailed
    case permissionDenied
    var errorDescription: String? {
        switch self {
        case .noDisplay: return "No display found"
        case .noWindow: return "No window found"
        case .cropFailed: return "Failed to crop image"
        case .permissionDenied: return "Screen capture permission denied"
        }
    }
}
