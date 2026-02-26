import Foundation

enum ToolType: String, CaseIterable, Codable {
    case textSelect
    case hand
    case arrow
    case rectangle
    case ellipse
    case line
    case pencil
    case highlighter
    case text
    case blur
    case pixelate
    case spotlight
    case counter
    case crop

    var shortcutKey: String {
        switch self {
        case .textSelect: return "V"
        case .hand: return "M"
        case .arrow: return "A"
        case .rectangle: return "R"
        case .ellipse: return "E"
        case .line: return "L"
        case .pencil: return "P"
        case .highlighter: return "H"
        case .text: return "T"
        case .blur: return "B"
        case .pixelate: return "X"
        case .spotlight: return "S"
        case .counter: return "N"
        case .crop: return "C"
        }
    }

    var iconName: String {
        switch self {
        case .textSelect: return "text.cursor"
        case .hand: return "hand.draw"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .line: return "line.diagonal"
        case .pencil: return "pencil"
        case .highlighter: return "highlighter"
        case .text: return "textformat"
        case .blur: return "drop.halffull"
        case .pixelate: return "squareshape.split.3x3"
        case .spotlight: return "flashlight.on.fill"
        case .counter: return "number"
        case .crop: return "crop"
        }
    }

    var displayName: String {
        switch self {
        case .textSelect: return "Text Select"
        case .hand: return "Hand"
        case .arrow: return "Arrow"
        case .rectangle: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .line: return "Line"
        case .pencil: return "Pencil"
        case .highlighter: return "Highlighter"
        case .text: return "Text"
        case .blur: return "Blur"
        case .pixelate: return "Pixelate"
        case .spotlight: return "Spotlight"
        case .counter: return "Counter"
        case .crop: return "Crop"
        }
    }
}
