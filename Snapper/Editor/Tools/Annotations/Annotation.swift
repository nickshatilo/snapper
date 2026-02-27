import AppKit

protocol Annotation: AnyObject, Identifiable {
    var id: UUID { get }
    var type: ToolType { get }
    var zOrder: Int { get set }
    var isVisible: Bool { get set }
    var boundingRect: CGRect { get }

    func render(in context: CGContext)
    func hitTest(point: CGPoint) -> Bool
    func duplicate() -> any Annotation
}

extension Annotation {
    func hitTest(point: CGPoint) -> Bool {
        boundingRect.contains(point)
    }
}

enum AnnotationResizeHandle: CaseIterable {
    case topLeft
    case top
    case topRight
    case right
    case bottomRight
    case bottom
    case bottomLeft
    case left
}

enum AnnotationGeometry {
    private static let minResizeDimension: CGFloat = 8

    static func editableFrame(for annotation: any Annotation) -> CGRect {
        if let rectangle = annotation as? RectangleAnnotation {
            return rectangle.rect.standardized
        }
        if let ellipse = annotation as? EllipseAnnotation {
            return ellipse.rect.standardized
        }
        if let blur = annotation as? BlurAnnotation {
            return blur.rect.standardized
        }
        if let pixelate = annotation as? PixelateAnnotation {
            return pixelate.rect.standardized
        }
        if let spotlight = annotation as? SpotlightAnnotation {
            return spotlight.rect.standardized
        }
        if let crop = annotation as? CropAnnotation {
            return crop.rect.standardized
        }
        if let line = annotation as? LineAnnotation {
            return normalizedLineFrame(start: line.start, end: line.end)
        }
        if let arrow = annotation as? ArrowAnnotation {
            return normalizedLineFrame(start: arrow.start, end: arrow.end)
        }
        if let highlighter = annotation as? HighlighterAnnotation {
            return normalizedLineFrame(start: highlighter.start, end: highlighter.end)
        }
        if let text = annotation as? TextAnnotation {
            return text.boundingRect.standardized
        }
        if let counter = annotation as? CounterAnnotation {
            return counter.boundingRect.standardized
        }
        if let pencil = annotation as? PencilAnnotation {
            return pencil.boundingRect.standardized
        }

        return annotation.boundingRect.standardized
    }

    static func supportsResize(_ annotation: any Annotation) -> Bool {
        switch annotation {
        case is RectangleAnnotation, is EllipseAnnotation, is BlurAnnotation, is PixelateAnnotation,
             is SpotlightAnnotation, is CropAnnotation, is LineAnnotation, is ArrowAnnotation,
             is HighlighterAnnotation, is PencilAnnotation:
            return true
        default:
            return false
        }
    }

    static func supportsRotation(_ annotation: any Annotation) -> Bool {
        annotation is RectangleAnnotation
            || annotation is EllipseAnnotation
            || annotation is TextAnnotation
            || annotation is PencilAnnotation
            || annotation is LineAnnotation
    }

    static func rotationDegrees(for annotation: any Annotation) -> CGFloat {
        if let rectangle = annotation as? RectangleAnnotation {
            return rectangle.rotationDegrees
        }
        if let ellipse = annotation as? EllipseAnnotation {
            return ellipse.rotationDegrees
        }
        if let text = annotation as? TextAnnotation {
            return text.rotationDegrees
        }
        return 0
    }

    static func translated(_ annotation: any Annotation, by delta: CGPoint) -> (any Annotation)? {
        if let rectangle = annotation as? RectangleAnnotation {
            return RectangleAnnotation(
                id: rectangle.id,
                rect: rectangle.rect.offsetBy(dx: delta.x, dy: delta.y),
                strokeColor: rectangle.strokeColor,
                fillColor: rectangle.fillColor,
                strokeWidth: rectangle.strokeWidth,
                cornerRadius: rectangle.cornerRadius,
                rotationDegrees: rectangle.rotationDegrees
            )
        }
        if let ellipse = annotation as? EllipseAnnotation {
            return EllipseAnnotation(
                id: ellipse.id,
                rect: ellipse.rect.offsetBy(dx: delta.x, dy: delta.y),
                strokeColor: ellipse.strokeColor,
                fillColor: ellipse.fillColor,
                strokeWidth: ellipse.strokeWidth,
                rotationDegrees: ellipse.rotationDegrees
            )
        }
        if let line = annotation as? LineAnnotation {
            return LineAnnotation(
                id: line.id,
                start: line.start.offsetBy(dx: delta.x, dy: delta.y),
                end: line.end.offsetBy(dx: delta.x, dy: delta.y),
                color: line.color,
                strokeWidth: line.strokeWidth,
                isDashed: line.isDashed
            )
        }
        if let arrow = annotation as? ArrowAnnotation {
            return ArrowAnnotation(
                id: arrow.id,
                start: arrow.start.offsetBy(dx: delta.x, dy: delta.y),
                end: arrow.end.offsetBy(dx: delta.x, dy: delta.y),
                color: arrow.color,
                strokeWidth: arrow.strokeWidth,
                style: arrow.style
            )
        }
        if let highlighter = annotation as? HighlighterAnnotation {
            return HighlighterAnnotation(
                id: highlighter.id,
                start: highlighter.start.offsetBy(dx: delta.x, dy: delta.y),
                end: highlighter.end.offsetBy(dx: delta.x, dy: delta.y),
                color: highlighter.color,
                strokeWidth: highlighter.strokeWidth
            )
        }
        if let text = annotation as? TextAnnotation {
            let copy = TextAnnotation(
                id: text.id,
                position: text.position.offsetBy(dx: delta.x, dy: delta.y),
                text: text.text,
                fontName: text.fontName,
                fontSize: text.fontSize,
                color: text.color,
                rotationDegrees: text.rotationDegrees
            )
            copy.isBold = text.isBold
            copy.isItalic = text.isItalic
            copy.hasBackground = text.hasBackground
            return copy
        }
        if let blur = annotation as? BlurAnnotation {
            return BlurAnnotation(
                id: blur.id,
                rect: blur.rect.offsetBy(dx: delta.x, dy: delta.y),
                intensity: blur.intensity,
                sourceImage: blur.sourceImage
            )
        }
        if let pixelate = annotation as? PixelateAnnotation {
            return PixelateAnnotation(
                id: pixelate.id,
                rect: pixelate.rect.offsetBy(dx: delta.x, dy: delta.y),
                blockSize: pixelate.blockSize,
                sourceImage: pixelate.sourceImage
            )
        }
        if let spotlight = annotation as? SpotlightAnnotation {
            return SpotlightAnnotation(
                id: spotlight.id,
                rect: spotlight.rect.offsetBy(dx: delta.x, dy: delta.y),
                dimOpacity: spotlight.dimOpacity
            )
        }
        if let counter = annotation as? CounterAnnotation {
            return CounterAnnotation(
                id: counter.id,
                position: counter.position.offsetBy(dx: delta.x, dy: delta.y),
                value: counter.value,
                style: counter.style,
                color: counter.color
            )
        }
        if let crop = annotation as? CropAnnotation {
            return CropAnnotation(
                id: crop.id,
                rect: crop.rect.offsetBy(dx: delta.x, dy: delta.y)
            )
        }
        if let pencil = annotation as? PencilAnnotation {
            let movedPoints = pencil.points.map { $0.offsetBy(dx: delta.x, dy: delta.y) }
            return PencilAnnotation(
                id: pencil.id,
                points: movedPoints,
                color: pencil.color,
                strokeWidth: pencil.strokeWidth
            )
        }

        return nil
    }

    static func resized(
        _ annotation: any Annotation,
        from originalFrame: CGRect,
        to candidateFrame: CGRect
    ) -> (any Annotation)? {
        let frame = normalizedResizedFrame(candidateFrame)
        guard frame.width >= minResizeDimension, frame.height >= minResizeDimension else {
            return nil
        }

        if let rectangle = annotation as? RectangleAnnotation {
            return RectangleAnnotation(
                id: rectangle.id,
                rect: frame,
                strokeColor: rectangle.strokeColor,
                fillColor: rectangle.fillColor,
                strokeWidth: rectangle.strokeWidth,
                cornerRadius: rectangle.cornerRadius,
                rotationDegrees: rectangle.rotationDegrees
            )
        }
        if let ellipse = annotation as? EllipseAnnotation {
            return EllipseAnnotation(
                id: ellipse.id,
                rect: frame,
                strokeColor: ellipse.strokeColor,
                fillColor: ellipse.fillColor,
                strokeWidth: ellipse.strokeWidth,
                rotationDegrees: ellipse.rotationDegrees
            )
        }
        if let blur = annotation as? BlurAnnotation {
            return BlurAnnotation(
                id: blur.id,
                rect: frame,
                intensity: blur.intensity,
                sourceImage: blur.sourceImage
            )
        }
        if let pixelate = annotation as? PixelateAnnotation {
            return PixelateAnnotation(
                id: pixelate.id,
                rect: frame,
                blockSize: pixelate.blockSize,
                sourceImage: pixelate.sourceImage
            )
        }
        if let spotlight = annotation as? SpotlightAnnotation {
            return SpotlightAnnotation(
                id: spotlight.id,
                rect: frame,
                dimOpacity: spotlight.dimOpacity
            )
        }
        if let crop = annotation as? CropAnnotation {
            return CropAnnotation(id: crop.id, rect: frame)
        }

        if let line = annotation as? LineAnnotation {
            return LineAnnotation(
                id: line.id,
                start: remap(point: line.start, from: originalFrame, to: frame),
                end: remap(point: line.end, from: originalFrame, to: frame),
                color: line.color,
                strokeWidth: line.strokeWidth,
                isDashed: line.isDashed
            )
        }
        if let arrow = annotation as? ArrowAnnotation {
            return ArrowAnnotation(
                id: arrow.id,
                start: remap(point: arrow.start, from: originalFrame, to: frame),
                end: remap(point: arrow.end, from: originalFrame, to: frame),
                color: arrow.color,
                strokeWidth: arrow.strokeWidth,
                style: arrow.style
            )
        }
        if let highlighter = annotation as? HighlighterAnnotation {
            return HighlighterAnnotation(
                id: highlighter.id,
                start: remap(point: highlighter.start, from: originalFrame, to: frame),
                end: remap(point: highlighter.end, from: originalFrame, to: frame),
                color: highlighter.color,
                strokeWidth: highlighter.strokeWidth
            )
        }
        if let pencil = annotation as? PencilAnnotation {
            let remappedPoints = pencil.points.map { remap(point: $0, from: originalFrame, to: frame) }
            return PencilAnnotation(
                id: pencil.id,
                points: remappedPoints,
                color: pencil.color,
                strokeWidth: pencil.strokeWidth
            )
        }

        return nil
    }

    static func rotated(_ annotation: any Annotation, to rotationDegrees: CGFloat) -> (any Annotation)? {
        if let rectangle = annotation as? RectangleAnnotation {
            return RectangleAnnotation(
                id: rectangle.id,
                rect: rectangle.rect,
                strokeColor: rectangle.strokeColor,
                fillColor: rectangle.fillColor,
                strokeWidth: rectangle.strokeWidth,
                cornerRadius: rectangle.cornerRadius,
                rotationDegrees: rotationDegrees
            )
        }
        if let ellipse = annotation as? EllipseAnnotation {
            return EllipseAnnotation(
                id: ellipse.id,
                rect: ellipse.rect,
                strokeColor: ellipse.strokeColor,
                fillColor: ellipse.fillColor,
                strokeWidth: ellipse.strokeWidth,
                rotationDegrees: rotationDegrees
            )
        }
        if let text = annotation as? TextAnnotation {
            let copy = TextAnnotation(
                id: text.id,
                position: text.position,
                text: text.text,
                fontName: text.fontName,
                fontSize: text.fontSize,
                color: text.color,
                rotationDegrees: rotationDegrees
            )
            copy.isBold = text.isBold
            copy.isItalic = text.isItalic
            copy.hasBackground = text.hasBackground
            return copy
        }
        if let pencil = annotation as? PencilAnnotation {
            let frame = pencil.boundingRect.standardized
            let center = CGPoint(x: frame.midX, y: frame.midY)
            let rotationRadians = rotationDegrees * (.pi / 180)
            let rotatedPoints = pencil.points.map { rotate($0, around: center, by: rotationRadians) }
            return PencilAnnotation(
                id: pencil.id,
                points: rotatedPoints,
                color: pencil.color,
                strokeWidth: pencil.strokeWidth
            )
        }
        if let line = annotation as? LineAnnotation {
            let frame = normalizedLineFrame(start: line.start, end: line.end)
            let center = CGPoint(x: frame.midX, y: frame.midY)
            let rotationRadians = rotationDegrees * (.pi / 180)
            return LineAnnotation(
                id: line.id,
                start: rotate(line.start, around: center, by: rotationRadians),
                end: rotate(line.end, around: center, by: rotationRadians),
                color: line.color,
                strokeWidth: line.strokeWidth,
                isDashed: line.isDashed
            )
        }

        return nil
    }

    static func rectForResize(
        handle: AnnotationResizeHandle,
        originalFrame: CGRect,
        currentPoint: CGPoint
    ) -> CGRect {
        var minX = originalFrame.minX
        var maxX = originalFrame.maxX
        var minY = originalFrame.minY
        var maxY = originalFrame.maxY

        switch handle {
        case .topLeft:
            minX = currentPoint.x
            maxY = currentPoint.y
        case .top:
            maxY = currentPoint.y
        case .topRight:
            maxX = currentPoint.x
            maxY = currentPoint.y
        case .right:
            maxX = currentPoint.x
        case .bottomRight:
            maxX = currentPoint.x
            minY = currentPoint.y
        case .bottom:
            minY = currentPoint.y
        case .bottomLeft:
            minX = currentPoint.x
            minY = currentPoint.y
        case .left:
            minX = currentPoint.x
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).standardized
    }

    private static func normalizedLineFrame(start: CGPoint, end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: max(abs(end.x - start.x), minResizeDimension),
            height: max(abs(end.y - start.y), minResizeDimension)
        ).standardized
    }

    private static func normalizedResizedFrame(_ frame: CGRect) -> CGRect {
        frame.standardized
    }

    private static func remap(point: CGPoint, from source: CGRect, to target: CGRect) -> CGPoint {
        let safeSourceWidth = max(source.width, 1)
        let safeSourceHeight = max(source.height, 1)
        let normalizedX = (point.x - source.minX) / safeSourceWidth
        let normalizedY = (point.y - source.minY) / safeSourceHeight

        return CGPoint(
            x: target.minX + normalizedX * target.width,
            y: target.minY + normalizedY * target.height
        )
    }

    private static func rotate(_ point: CGPoint, around center: CGPoint, by angle: CGFloat) -> CGPoint {
        let translatedX = point.x - center.x
        let translatedY = point.y - center.y
        let rotatedX = translatedX * cos(angle) - translatedY * sin(angle)
        let rotatedY = translatedX * sin(angle) + translatedY * cos(angle)
        return CGPoint(x: center.x + rotatedX, y: center.y + rotatedY)
    }
}

private extension CGPoint {
    func offsetBy(dx: CGFloat, dy: CGFloat) -> CGPoint {
        CGPoint(x: x + dx, y: y + dy)
    }
}
