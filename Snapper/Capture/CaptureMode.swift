import Foundation

enum CaptureMode: String, CaseIterable, Codable {
    case fullscreen
    case area
    case window
    case ocr
    case timer

    var displayName: String {
        switch self {
        case .fullscreen: return "Fullscreen"
        case .area: return "Area"
        case .window: return "Window"
        case .ocr: return "OCR"
        case .timer: return "Timer"
        }
    }

    var iconName: String {
        switch self {
        case .fullscreen: return "rectangle.dashed"
        case .area: return "crop"
        case .window: return "macwindow"
        case .ocr: return "text.viewfinder"
        case .timer: return "timer"
        }
    }
}
