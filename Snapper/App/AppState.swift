import AppKit
import Foundation
import SwiftUI

@Observable
final class AppState {
    private let defaults: UserDefaults
    private var pendingDefaults: [String: Any] = [:]
    private var flushWorkItem: DispatchWorkItem?

    var isFirstRun: Bool {
        didSet { enqueueDefault(!isFirstRun, forKey: Constants.Keys.hasLaunchedBefore) }
    }

    var isCapturing = false

    var menuBarVisible: Bool {
        didSet { enqueueDefault(menuBarVisible, forKey: Constants.Keys.menuBarVisible) }
    }

    var launchAtLogin: Bool {
        didSet { enqueueDefault(launchAtLogin, forKey: Constants.Keys.launchAtLogin) }
    }

    var captureSound: Bool {
        didSet { enqueueDefault(captureSound, forKey: Constants.Keys.captureSound) }
    }

    var captureSoundName: CaptureSound {
        didSet { enqueueDefault(captureSoundName.rawValue, forKey: Constants.Keys.captureSoundName) }
    }

    var copyToClipboard: Bool {
        didSet { enqueueDefault(copyToClipboard, forKey: Constants.Keys.copyToClipboard) }
    }

    var saveToFile: Bool {
        didSet { enqueueDefault(saveToFile, forKey: Constants.Keys.saveToFile) }
    }

    var saveDirectory: URL {
        didSet { enqueueDefault(saveDirectory.path, forKey: Constants.Keys.saveDirectory) }
    }

    var imageFormat: ImageFormat {
        didSet { enqueueDefault(imageFormat.rawValue, forKey: Constants.Keys.imageFormat) }
    }

    var jpegQuality: Double {
        didSet { enqueueDefault(jpegQuality, forKey: Constants.Keys.jpegQuality) }
    }

    var filenamePattern: String {
        didSet { enqueueDefault(filenamePattern, forKey: Constants.Keys.filenamePattern) }
    }

    var showCrosshair: Bool {
        didSet { enqueueDefault(showCrosshair, forKey: Constants.Keys.showCrosshair) }
    }

    var showMagnifier: Bool {
        didSet { enqueueDefault(showMagnifier, forKey: Constants.Keys.showMagnifier) }
    }

    var freezeScreen: Bool {
        didSet { enqueueDefault(freezeScreen, forKey: Constants.Keys.freezeScreen) }
    }

    var retina2x: Bool {
        didSet { enqueueDefault(retina2x, forKey: Constants.Keys.retina2x) }
    }

    var windowCaptureIncludeShadow: Bool {
        didSet { enqueueDefault(windowCaptureIncludeShadow, forKey: Constants.Keys.windowCaptureIncludeShadow) }
    }

    var overlayCorner: OverlayCorner {
        didSet {
            enqueueDefault(overlayCorner.rawValue, forKey: Constants.Keys.overlayCorner)
            NotificationCenter.default.post(name: .overlayCornerChanged, object: nil)
        }
    }

    var historyRetentionDays: Int {
        didSet { enqueueDefault(historyRetentionDays, forKey: Constants.Keys.historyRetentionDays) }
    }

    var defaultPinnedOpacity: Double {
        didSet {
            enqueueDefault(defaultPinnedOpacity, forKey: Constants.Keys.defaultPinnedOpacity)
            NotificationCenter.default.post(name: .pinnedOpacityChanged, object: nil)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        self.isFirstRun = !defaults.bool(forKey: Constants.Keys.hasLaunchedBefore)
        self.menuBarVisible = defaults.object(forKey: Constants.Keys.menuBarVisible) as? Bool ?? true
        self.launchAtLogin = defaults.bool(forKey: Constants.Keys.launchAtLogin)
        self.captureSound = defaults.object(forKey: Constants.Keys.captureSound) as? Bool ?? false
        if let raw = defaults.string(forKey: Constants.Keys.captureSoundName),
           let sound = CaptureSound(rawValue: raw) {
            self.captureSoundName = sound
        } else {
            self.captureSoundName = .glass
        }
        self.copyToClipboard = defaults.object(forKey: Constants.Keys.copyToClipboard) as? Bool ?? true
        self.saveToFile = defaults.object(forKey: Constants.Keys.saveToFile) as? Bool ?? true

        if let path = defaults.string(forKey: Constants.Keys.saveDirectory) {
            self.saveDirectory = URL(fileURLWithPath: path)
        } else {
            self.saveDirectory = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory())
        }

        if let raw = defaults.string(forKey: Constants.Keys.imageFormat),
           let format = ImageFormat(rawValue: raw) {
            self.imageFormat = format
        } else {
            self.imageFormat = .png
        }

        self.jpegQuality = defaults.object(forKey: Constants.Keys.jpegQuality) as? Double ?? 0.9
        self.filenamePattern = defaults.string(forKey: Constants.Keys.filenamePattern) ?? Constants.Defaults.filenamePattern
        self.showCrosshair = defaults.object(forKey: Constants.Keys.showCrosshair) as? Bool ?? true
        self.showMagnifier = defaults.object(forKey: Constants.Keys.showMagnifier) as? Bool ?? false
        self.freezeScreen = defaults.bool(forKey: Constants.Keys.freezeScreen)
        self.retina2x = defaults.object(forKey: Constants.Keys.retina2x) as? Bool ?? true
        self.windowCaptureIncludeShadow = defaults.object(forKey: Constants.Keys.windowCaptureIncludeShadow) as? Bool ?? true

        if let raw = defaults.string(forKey: Constants.Keys.overlayCorner),
           let corner = OverlayCorner(rawValue: raw) {
            self.overlayCorner = corner
        } else {
            self.overlayCorner = .bottomRight
        }

        self.historyRetentionDays = defaults.object(forKey: Constants.Keys.historyRetentionDays) as? Int ?? 30
        self.defaultPinnedOpacity = defaults.object(forKey: Constants.Keys.defaultPinnedOpacity) as? Double ?? 1.0
    }

    private func enqueueDefault(_ value: Any, forKey key: String) {
        pendingDefaults[key] = value
        flushWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.flushDefaults()
        }
        flushWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    func flushDefaults() {
        flushWorkItem?.cancel()
        flushWorkItem = nil
        guard !pendingDefaults.isEmpty else { return }
        for (key, value) in pendingDefaults {
            defaults.set(value, forKey: key)
        }
        pendingDefaults.removeAll()
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

enum CaptureSound: String, CaseIterable {
    case cameraShot
    case glass
    case tink
    case pop
    case funk
    case hero
    case submarine

    var displayName: String {
        switch self {
        case .cameraShot: return "Camera Shot"
        case .glass: return "Glass"
        case .tink: return "Tink"
        case .pop: return "Pop"
        case .funk: return "Funk"
        case .hero: return "Hero"
        case .submarine: return "Submarine"
        }
    }

    var nsSoundName: NSSound.Name {
        switch self {
        case .cameraShot: return NSSound.Name("PhotoShutter")
        case .glass: return NSSound.Name("Glass")
        case .tink: return NSSound.Name("Tink")
        case .pop: return NSSound.Name("Pop")
        case .funk: return NSSound.Name("Funk")
        case .hero: return NSSound.Name("Hero")
        case .submarine: return NSSound.Name("Submarine")
        }
    }
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
