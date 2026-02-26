import Foundation

enum Constants {
    enum Keys {
        static let hasLaunchedBefore = "hasLaunchedBefore"
        static let menuBarVisible = "menuBarVisible"
        static let launchAtLogin = "launchAtLogin"
        static let captureSound = "captureSound"
        static let copyToClipboard = "copyToClipboard"
        static let saveToFile = "saveToFile"
        static let saveDirectory = "saveDirectory"
        static let imageFormat = "imageFormat"
        static let jpegQuality = "jpegQuality"
        static let filenamePattern = "filenamePattern"
        static let showCrosshair = "showCrosshair"
        static let showMagnifier = "showMagnifier"
        static let freezeScreen = "freezeScreen"
        static let retina2x = "retina2x"
        static let overlayCorner = "overlayCorner"
        static let historyRetentionDays = "historyRetentionDays"
        static let defaultPinnedOpacity = "defaultPinnedOpacity"
        static let pinnedScreenshots = "pinnedScreenshots"
        static let windowCaptureIncludeShadow = "windowCaptureIncludeShadow"
        static let hideDesktopIcons = "hideDesktopIcons"
        static let autoCheckUpdates = "autoCheckUpdates"
    }

    enum Defaults {
        static let filenamePattern = "Snapper {date} at {time}"
        static let thumbnailWidth: CGFloat = 300
        static let overlayWidth: CGFloat = 320
        static let magnifierSize: CGFloat = 120
        static let magnifierZoom: CGFloat = 8
    }

    enum App {
        static let name = "Snapper"
        static let bundleIdentifier = "com.snapper.app"
        static let githubURL = "https://github.com/snapper-app/snapper"
        static let supportDirectory: URL = {
            let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("Snapper")
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }()
        static let historyDirectory: URL = {
            let url = supportDirectory.appendingPathComponent("History")
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }()
    }
}
