import AppKit

@Observable
final class ToolManager {
    var currentTool: ToolType = .textSelect
    var strokeColor: NSColor = .systemRed {
        didSet {
            // Keep fill color in sync with stroke hue when fill is enabled.
            guard let fill = fillColor else { return }
            let alpha = max(fill.alphaComponent, 0.3)
            fillColor = strokeColor.withAlphaComponent(alpha)
        }
    }
    var strokeWidth: CGFloat = 3.0
    var fillColor: NSColor? = nil
    var fontSize: CGFloat = 16
    var fontName: String = "Helvetica"
    var arrowStyle: ArrowStyle = .straight
    var cornerRadius: CGFloat = 0
    var isDashed: Bool = false
    var blurIntensity: CGFloat = 10
    var pixelateBlockSize: CGFloat = 10
    var spotlightDimOpacity: CGFloat = 0.6
    var counterStyle: CounterStyle = .numbers

    // Active drawing state
    private var activeAnnotation: (any Annotation)?
    private var dragStartPoint: NSPoint?
    private var pencilPoints: [NSPoint] = []
    private var counterValue: Int = 1

    func mouseDown(at point: NSPoint, canvasState: CanvasState) {
        dragStartPoint = point

        switch currentTool {
        case .textSelect:
            break
        case .hand:
            break
        case .pencil:
            pencilPoints = [point]
        case .text:
            let annotation = TextAnnotation(
                position: point,
                text: "Text",
                fontName: fontName,
                fontSize: fontSize,
                color: strokeColor
            )
            canvasState.addAnnotation(annotation)
        case .counter:
            let annotation = CounterAnnotation(
                position: point,
                value: counterValue,
                style: counterStyle,
                color: strokeColor
            )
            canvasState.addAnnotation(annotation)
            counterValue += 1
        default:
            break
        }
    }

    func mouseDragged(to point: NSPoint, canvasState: CanvasState) {
        guard let start = dragStartPoint else { return }

        // Remove previous in-progress annotation
        if let active = activeAnnotation {
            canvasState.annotations.removeAll { $0.id == active.id }
        }

        let annotation: (any Annotation)?

        switch currentTool {
        case .textSelect:
            annotation = nil
        case .hand:
            annotation = nil
        case .arrow:
            annotation = ArrowAnnotation(
                start: start,
                end: point,
                color: strokeColor,
                strokeWidth: strokeWidth,
                style: arrowStyle
            )
        case .rectangle:
            let rect = CGRect(
                x: min(start.x, point.x),
                y: min(start.y, point.y),
                width: abs(point.x - start.x),
                height: abs(point.y - start.y)
            )
            annotation = RectangleAnnotation(
                rect: rect,
                strokeColor: strokeColor,
                fillColor: fillColor,
                strokeWidth: strokeWidth,
                cornerRadius: cornerRadius
            )
        case .ellipse:
            let rect = CGRect(
                x: min(start.x, point.x),
                y: min(start.y, point.y),
                width: abs(point.x - start.x),
                height: abs(point.y - start.y)
            )
            annotation = EllipseAnnotation(
                rect: rect,
                strokeColor: strokeColor,
                fillColor: fillColor,
                strokeWidth: strokeWidth
            )
        case .line:
            annotation = LineAnnotation(
                start: start,
                end: point,
                color: strokeColor,
                strokeWidth: strokeWidth,
                isDashed: isDashed
            )
        case .pencil:
            pencilPoints.append(point)
            annotation = PencilAnnotation(
                points: pencilPoints,
                color: strokeColor,
                strokeWidth: strokeWidth
            )
        case .highlighter:
            annotation = HighlighterAnnotation(
                start: start,
                end: point,
                color: strokeColor,
                strokeWidth: max(strokeWidth * 4, 20)
            )
        case .blur:
            let rect = CGRect(
                x: min(start.x, point.x),
                y: min(start.y, point.y),
                width: abs(point.x - start.x),
                height: abs(point.y - start.y)
            )
            annotation = BlurAnnotation(rect: rect, intensity: blurIntensity)
        case .pixelate:
            let rect = CGRect(
                x: min(start.x, point.x),
                y: min(start.y, point.y),
                width: abs(point.x - start.x),
                height: abs(point.y - start.y)
            )
            annotation = PixelateAnnotation(rect: rect, blockSize: pixelateBlockSize)
        case .spotlight:
            let rect = CGRect(
                x: min(start.x, point.x),
                y: min(start.y, point.y),
                width: abs(point.x - start.x),
                height: abs(point.y - start.y)
            )
            annotation = SpotlightAnnotation(rect: rect, dimOpacity: spotlightDimOpacity)
        case .crop:
            let rect = CGRect(
                x: min(start.x, point.x),
                y: min(start.y, point.y),
                width: abs(point.x - start.x),
                height: abs(point.y - start.y)
            )
            annotation = CropAnnotation(rect: rect)
        default:
            annotation = nil
        }

        if let annotation {
            activeAnnotation = annotation
            canvasState.annotations.append(annotation)
        }
    }

    func mouseUp(at point: NSPoint, canvasState: CanvasState) {
        if let active = activeAnnotation {
            // Commit the annotation properly via addAnnotation for undo support
            canvasState.annotations.removeAll { $0.id == active.id }
            canvasState.addAnnotation(active)
        }
        activeAnnotation = nil
        dragStartPoint = nil
        pencilPoints = []
    }
}

enum ArrowStyle: String, CaseIterable, Codable {
    case straight, curved, tapered, outlined

    var displayName: String { rawValue.capitalized }
}

enum CounterStyle: String, CaseIterable, Codable {
    case numbers, letters, roman

    var displayName: String { rawValue.capitalized }

    func display(for value: Int) -> String {
        switch self {
        case .numbers: return "\(value)"
        case .letters:
            let letter = Character(UnicodeScalar(64 + min(value, 26))!)
            return String(letter)
        case .roman: return romanNumeral(value)
        }
    }

    private func romanNumeral(_ num: Int) -> String {
        let values = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1]
        let symbols = ["M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I"]
        var result = ""
        var remaining = num
        for (i, value) in values.enumerated() {
            while remaining >= value {
                result += symbols[i]
                remaining -= value
            }
        }
        return result
    }
}
