import Foundation

enum HotkeyAction: String, CaseIterable, Codable {
    case captureFullscreen
    case captureArea
    case captureWindow
    case captureScroll
    case ocrCapture
    case timerCapture
    case allInOneHUD
    case toggleDesktopIcons

    var displayName: String {
        switch self {
        case .captureFullscreen: return "Capture Fullscreen"
        case .captureArea: return "Capture Area"
        case .captureWindow: return "Capture Window"
        case .captureScroll: return "Capture Scroll"
        case .ocrCapture: return "OCR Text Recognition"
        case .timerCapture: return "Timer Capture"
        case .allInOneHUD: return "All-in-One HUD"
        case .toggleDesktopIcons: return "Toggle Desktop Icons"
        }
    }

    var captureMode: CaptureMode? {
        switch self {
        case .captureFullscreen: return .fullscreen
        case .captureArea: return .area
        case .captureWindow: return .window
        case .captureScroll: return .scroll
        case .ocrCapture: return .ocr
        case .timerCapture: return .timer
        case .allInOneHUD: return nil
        case .toggleDesktopIcons: return nil
        }
    }
}
