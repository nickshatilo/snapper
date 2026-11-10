import Foundation

enum CaptureMode: String, CaseIterable, Codable {
    case fullscreen
    case area
    case window
    case scroll
    case ocr
    case timer

    var displayName: String {
        switch self {
        case .fullscreen: return "Fullscreen"
        case .area: return "Area"
        case .window: return "Window"
        case .scroll: return "Scroll"
        case .ocr: return "OCR"
        case .timer: return "Timer"
        }
    }
}
