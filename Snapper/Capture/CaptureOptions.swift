import Foundation

struct CaptureOptions {
    var freezeScreen: Bool = false
    var playSound: Bool = false
    var captureSound: CaptureSound = .glass
    var copyToClipboard: Bool = true
    var saveToFile: Bool = true
    var format: ImageFormat = .png
    var saveDirectory: URL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
    var filenamePattern: String = Constants.Defaults.filenamePattern
    var includeShadow: Bool = true
    var retina2x: Bool = true
    var jpegQuality: Double = 0.9

    static func from(appState: AppState) -> CaptureOptions {
        CaptureOptions(
            freezeScreen: appState.freezeScreen,
            playSound: appState.captureSound,
            captureSound: appState.captureSoundName,
            copyToClipboard: appState.copyToClipboard,
            saveToFile: appState.saveToFile,
            format: appState.imageFormat,
            saveDirectory: appState.saveDirectory,
            filenamePattern: appState.filenamePattern,
            retina2x: appState.retina2x,
            jpegQuality: appState.jpegQuality
        )
    }
}
