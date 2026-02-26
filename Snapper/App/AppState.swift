import Foundation
import SwiftUI

@Observable
final class AppState {
    var isFirstRun: Bool {
        get { !UserDefaults.standard.bool(forKey: Constants.Keys.hasLaunchedBefore) }
        set { UserDefaults.standard.set(!newValue, forKey: Constants.Keys.hasLaunchedBefore) }
    }

    var isCapturing = false
    var menuBarVisible: Bool {
        get { UserDefaults.standard.object(forKey: Constants.Keys.menuBarVisible) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Constants.Keys.menuBarVisible) }
    }

    var launchAtLogin: Bool {
        get { UserDefaults.standard.bool(forKey: Constants.Keys.launchAtLogin) }
        set { UserDefaults.standard.set(newValue, forKey: Constants.Keys.launchAtLogin) }
    }

    var captureSound: Bool {
        get { UserDefaults.standard.object(forKey: Constants.Keys.captureSound) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: Constants.Keys.captureSound) }
    }

    var copyToClipboard: Bool {
        get { UserDefaults.standard.object(forKey: Constants.Keys.copyToClipboard) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Constants.Keys.copyToClipboard) }
    }

    var saveToFile: Bool {
        get { UserDefaults.standard.object(forKey: Constants.Keys.saveToFile) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Constants.Keys.saveToFile) }
    }

    var saveDirectory: URL {
        get {
            if let path = UserDefaults.standard.string(forKey: Constants.Keys.saveDirectory) {
                return URL(fileURLWithPath: path)
            }
            return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        }
        set { UserDefaults.standard.set(newValue.path, forKey: Constants.Keys.saveDirectory) }
    }

    var imageFormat: ImageFormat {
        get {
            if let raw = UserDefaults.standard.string(forKey: Constants.Keys.imageFormat),
               let format = ImageFormat(rawValue: raw) {
                return format
            }
            return .png
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Constants.Keys.imageFormat) }
    }

    var jpegQuality: Double {
        get { UserDefaults.standard.object(forKey: Constants.Keys.jpegQuality) as? Double ?? 0.9 }
        set { UserDefaults.standard.set(newValue, forKey: Constants.Keys.jpegQuality) }
    }

    var filenamePattern: String {
        get { UserDefaults.standard.string(forKey: Constants.Keys.filenamePattern) ?? Constants.Defaults.filenamePattern }
        set { UserDefaults.standard.set(newValue, forKey: Constants.Keys.filenamePattern) }
    }

    var showCrosshair: Bool {
        get { UserDefaults.standard.object(forKey: Constants.Keys.showCrosshair) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Constants.Keys.showCrosshair) }
    }

    var showMagnifier: Bool {
        get { UserDefaults.standard.object(forKey: Constants.Keys.showMagnifier) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Constants.Keys.showMagnifier) }
    }

    var freezeScreen: Bool {
        get { UserDefaults.standard.bool(forKey: Constants.Keys.freezeScreen) }
        set { UserDefaults.standard.set(newValue, forKey: Constants.Keys.freezeScreen) }
    }

    var retina2x: Bool {
        get { UserDefaults.standard.object(forKey: Constants.Keys.retina2x) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Constants.Keys.retina2x) }
    }

    var overlayCorner: OverlayCorner {
        get {
            if let raw = UserDefaults.standard.string(forKey: Constants.Keys.overlayCorner),
               let corner = OverlayCorner(rawValue: raw) {
                return corner
            }
            return .bottomRight
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Constants.Keys.overlayCorner) }
    }

    var historyRetentionDays: Int {
        get { UserDefaults.standard.object(forKey: Constants.Keys.historyRetentionDays) as? Int ?? 30 }
        set { UserDefaults.standard.set(newValue, forKey: Constants.Keys.historyRetentionDays) }
    }

    var defaultPinnedOpacity: Double {
        get { UserDefaults.standard.object(forKey: Constants.Keys.defaultPinnedOpacity) as? Double ?? 1.0 }
        set { UserDefaults.standard.set(newValue, forKey: Constants.Keys.defaultPinnedOpacity) }
    }
}

enum ImageFormat: String, CaseIterable {
    case png = "png"
    case jpeg = "jpeg"
    case tiff = "tiff"

    var displayName: String {
        switch self {
        case .png: return "PNG"
        case .jpeg: return "JPEG"
        case .tiff: return "TIFF"
        }
    }

    var utType: String {
        switch self {
        case .png: return "public.png"
        case .jpeg: return "public.jpeg"
        case .tiff: return "public.tiff"
        }
    }

    var fileExtension: String { rawValue }
}

enum OverlayCorner: String, CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight

    var displayName: String {
        switch self {
        case .topLeft: return "Top Left"
        case .topRight: return "Top Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        }
    }
}
