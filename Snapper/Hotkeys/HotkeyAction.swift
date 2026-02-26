import Foundation

enum HotkeyAction: String, CaseIterable, Codable {
    case captureFullscreen
    case captureArea
    case captureWindow
    case scrollingCapture
    case ocrCapture
    case timerCapture
    case toggleDesktopIcons

    var displayName: String {
        switch self {
        case .captureFullscreen: return "Capture Fullscreen"
        case .captureArea: return "Capture Area"
        case .captureWindow: return "Capture Window"
        case .scrollingCapture: return "Scrolling Capture"
        case .ocrCapture: return "OCR Text Recognition"
        case .timerCapture: return "Timer Capture"
        case .toggleDesktopIcons: return "Toggle Desktop Icons"
        }
    }

    var captureMode: CaptureMode? {
        switch self {
        case .captureFullscreen: return .fullscreen
        case .captureArea: return .area
        case .captureWindow: return .window
        case .scrollingCapture: return .scrolling
        case .ocrCapture: return .ocr
        case .timerCapture: return .timer
        case .toggleDesktopIcons: return nil
        }
    }
}
