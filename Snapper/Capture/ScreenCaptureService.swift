import AppKit
import ScreenCaptureKit

final class ScreenCaptureService {
    struct RectCaptureContext {
        fileprivate let displayFrame: CGRect
        fileprivate let displayScale: CGFloat
        fileprivate let filter: SCContentFilter
        fileprivate let configuration: SCStreamConfiguration
    }

    func captureDisplay(_ display: SCDisplay? = nil) async throws -> CGImage {
        try ensureScreenCapturePermission()
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let targetDisplay = display ?? content.displays.first!

        let filter = SCContentFilter(display: targetDisplay, excludingWindows: [])
        let config = SCStreamConfiguration()
        let scale = displayScaleFactor(for: targetDisplay)
        config.width = max(1, Int(CGFloat(targetDisplay.width) * scale))
        config.height = max(1, Int(CGFloat(targetDisplay.height) * scale))
        config.showsCursor = false
        config.captureResolution = .best

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )
        return image
    }

    func captureWindow(_ window: SCWindow) async throws -> CGImage {
        try ensureScreenCapturePermission()
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        let scale = displayScale(for: window.frame, in: content)
        config.width = max(1, Int(window.frame.width * scale))
        config.height = max(1, Int(window.frame.height * scale))
        config.showsCursor = false
        config.captureResolution = .best
        config.shouldBeOpaque = false

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )
        return image
    }

    func captureRect(_ rect: CGRect) async throws -> CGImage {
        try ensureScreenCapturePermission()
        let context = try await prepareRectCapture(for: rect)
        return try await captureRect(rect, using: context)
    }

    func prepareRectCapture(
        for rect: CGRect,
        content: SCShareableContent? = nil,
        excludingWindowIDs: [CGWindowID] = []
    ) async throws -> RectCaptureContext {
        try ensureScreenCapturePermission()
        let resolvedContent: SCShareableContent
        if let content {
            resolvedContent = content
        } else {
            resolvedContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
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

        let scale = displayScaleFactor(for: display)
        let excludedWindows: [SCWindow]
        if excludingWindowIDs.isEmpty {
            excludedWindows = []
        } else {
            let excludedSet = Set(excludingWindowIDs)
            excludedWindows = resolvedContent.windows.filter { excludedSet.contains($0.windowID) }
        }
        let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
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

        // Convert from global point-space to display-local pixel-space.
        let localRect = CGRect(
            x: (rect.minX - context.displayFrame.minX) * context.displayScale,
            y: (context.displayFrame.maxY - rect.maxY) * context.displayScale,
            width: rect.width * context.displayScale,
            height: rect.height * context.displayScale
        ).integral

        let imageBounds = CGRect(x: 0, y: 0, width: fullImage.width, height: fullImage.height)
        let cropRect = localRect.intersection(imageBounds)
        guard cropRect.width > 0, cropRect.height > 0,
              let croppedImage = fullImage.cropping(to: cropRect) else {
            throw CaptureError.cropFailed
        }

        return croppedImage
    }

    func getShareableContent() async throws -> SCShareableContent {
        try ensureScreenCapturePermission()
        return try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }

    private func ensureScreenCapturePermission() throws {
        guard PermissionChecker.isScreenCaptureGranted() else {
            throw CaptureError.permissionDenied
        }
    }

    private func resolveDisplay(for rect: CGRect, in content: SCShareableContent) -> SCDisplay? {
        if let exactMatch = content.displays.first(where: {
            CGRect(
                x: CGFloat($0.frame.origin.x),
                y: CGFloat($0.frame.origin.y),
                width: CGFloat($0.frame.width),
                height: CGFloat($0.frame.height)
            ).contains(rect.origin)
        }) {
            return exactMatch
        }
        return content.displays.first(where: {
            CGRect(
                x: CGFloat($0.frame.origin.x),
                y: CGFloat($0.frame.origin.y),
                width: CGFloat($0.frame.width),
                height: CGFloat($0.frame.height)
            ).intersects(rect)
        }) ?? content.displays.first
    }

    private func displayScale(for rect: CGRect, in content: SCShareableContent) -> CGFloat {
        guard let display = resolveDisplay(for: rect, in: content) else { return 1 }
        return displayScaleFactor(for: display)
    }

    private func displayScaleFactor(for display: SCDisplay) -> CGFloat {
        for screen in NSScreen.screens {
            guard let screenID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                continue
            }
            if screenID == display.displayID {
                return max(1, screen.backingScaleFactor)
            }
        }
        return 2.0
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
