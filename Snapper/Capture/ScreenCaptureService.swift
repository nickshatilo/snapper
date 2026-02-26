import AppKit
import ScreenCaptureKit

final class ScreenCaptureService {
    func captureDisplay(_ display: SCDisplay? = nil) async throws -> CGImage {
        try ensureScreenCapturePermission()
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let targetDisplay = display ?? content.displays.first!

        let filter = SCContentFilter(display: targetDisplay, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = targetDisplay.width * 2
        config.height = targetDisplay.height * 2
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
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        config.width = Int(window.frame.width) * 2
        config.height = Int(window.frame.height) * 2
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
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { NSRect(x: CGFloat($0.frame.origin.x), y: CGFloat($0.frame.origin.y), width: CGFloat($0.width), height: CGFloat($0.height)).contains(rect.origin) }) ?? content.displays.first else {
            throw CaptureError.noDisplay
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.showsCursor = false
        config.captureResolution = .best

        // Capture full display then crop
        let displayScale = NSScreen.main?.backingScaleFactor ?? 2.0
        config.width = display.width * Int(displayScale)
        config.height = display.height * Int(displayScale)

        let fullImage = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config
        )

        // Convert rect to display-local coordinates
        let displayFrame = CGRect(x: CGFloat(display.frame.origin.x), y: CGFloat(display.frame.origin.y), width: CGFloat(display.width), height: CGFloat(display.height))
        let localRect = CGRect(
            x: (rect.origin.x - displayFrame.origin.x) * displayScale,
            y: (displayFrame.height - rect.origin.y - rect.height + displayFrame.origin.y) * displayScale,
            width: rect.width * displayScale,
            height: rect.height * displayScale
        )

        guard let croppedImage = fullImage.cropping(to: localRect) else {
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
}

enum CaptureError: Error, LocalizedError {
    case noDisplay
    case noWindow
    case cropFailed
    case permissionDenied
    case stitchingFailed

    var errorDescription: String? {
        switch self {
        case .noDisplay: return "No display found"
        case .noWindow: return "No window found"
        case .cropFailed: return "Failed to crop image"
        case .permissionDenied: return "Screen capture permission denied"
        case .stitchingFailed: return "Failed to stitch images"
        }
    }
}
