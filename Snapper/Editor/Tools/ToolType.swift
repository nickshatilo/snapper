import Foundation

enum ToolType: String, CaseIterable, Codable {
    case textSelect
    case ocr
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
        case .ocr: return "O"
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
        case .textSelect: return "cursorarrow"
        case .ocr: return "text.viewfinder"
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
        case .textSelect: return "Mouse"
        case .ocr: return "OCR"
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

enum PrimaryToolGroup: CaseIterable {
    case mouse
    case ocr
    case hand
    case text
    case draw
    case shapes
    case blur
    case crop

    var displayName: String {
        switch self {
        case .mouse: return "Mouse"
        case .ocr: return "OCR"
        case .hand: return "Hand"
        case .text: return "Text"
        case .draw: return "Draw"
        case .shapes: return "Shapes"
        case .blur: return "Blur"
        case .crop: return "Crop"
        }
    }

    var iconName: String {
        switch self {
        case .mouse: return "cursorarrow"
        case .ocr: return "text.viewfinder"
        case .hand: return "hand.draw"
        case .text: return "textformat"
        case .draw: return "pencil.tip"
        case .shapes: return "square.on.circle"
        case .blur: return "drop.halffull"
        case .crop: return "crop"
        }
    }
}

extension ToolType {
    var primaryGroup: PrimaryToolGroup {
        switch self {
        case .textSelect:
            return .mouse
        case .ocr:
            return .ocr
        case .hand:
            return .hand
        case .text:
            return .text
        case .pencil, .highlighter:
            return .draw
        case .arrow, .rectangle, .ellipse, .line, .counter:
            return .shapes
        case .blur, .pixelate:
            return .blur
        case .spotlight:
            return .blur
        case .crop:
            return .crop
        }
    }

    static func defaultTool(for group: PrimaryToolGroup) -> ToolType {
        switch group {
        case .mouse:
            return .textSelect
        case .ocr:
            return .ocr
        case .hand:
            return .hand
        case .text:
            return .text
        case .draw:
            return .pencil
        case .shapes:
            return .arrow
        case .blur:
            return .blur
        case .crop:
            return .crop
        }
    }

    static func tools(for group: PrimaryToolGroup) -> [ToolType] {
        switch group {
        case .mouse:
            return [.textSelect]
        case .ocr:
            return [.ocr]
        case .hand:
            return [.hand]
        case .text:
            return [.text]
        case .draw:
            return [.pencil, .highlighter]
        case .shapes:
            return [.arrow, .rectangle, .ellipse, .line, .counter]
        case .blur:
            return [.blur, .pixelate]
        case .crop:
            return [.crop]
        }
    }
}
