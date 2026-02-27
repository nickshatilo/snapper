import AppKit

final class EllipseAnnotation: Annotation {
    let id: UUID
    let type: ToolType = .ellipse
    var zOrder: Int = 0
    var isVisible: Bool = true

    let rect: CGRect
    let strokeColor: NSColor
    let fillColor: NSColor?
    let strokeWidth: CGFloat
    let rotationDegrees: CGFloat

    var boundingRect: CGRect {
        rotatedBounds(for: rect.insetBy(dx: -strokeWidth, dy: -strokeWidth))
    }

    init(
        id: UUID = UUID(),
        rect: CGRect,
        strokeColor: NSColor,
        fillColor: NSColor?,
        strokeWidth: CGFloat,
        rotationDegrees: CGFloat = 0
    ) {
        self.id = id
        self.rect = rect
        self.strokeColor = strokeColor
        self.fillColor = fillColor
        self.strokeWidth = strokeWidth
        self.rotationDegrees = rotationDegrees
    }

    func render(in context: CGContext) {
        context.saveGState()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: rotationRadians)
        context.translateBy(x: -center.x, y: -center.y)

        let path = CGPath(ellipseIn: rect, transform: nil)

        if let fill = fillColor {
            context.setFillColor(fill.cgColor)
            context.addPath(path)
            context.fillPath()
        }

        context.setStrokeColor(strokeColor.cgColor)
        context.setLineWidth(strokeWidth)
        context.addPath(path)
        context.strokePath()

        context.restoreGState()
    }

    func hitTest(point: CGPoint) -> Bool {
        let transformedPoint = rotate(point, around: CGPoint(x: rect.midX, y: rect.midY), by: -rotationRadians)
        return rect.insetBy(dx: -strokeWidth, dy: -strokeWidth).contains(transformedPoint)
    }

    func duplicate() -> any Annotation {
        EllipseAnnotation(
            id: id,
            rect: rect,
            strokeColor: strokeColor,
            fillColor: fillColor,
            strokeWidth: strokeWidth,
            rotationDegrees: rotationDegrees
        )
    }

    private var rotationRadians: CGFloat {
        rotationDegrees * (.pi / 180)
    }

    private func rotatedBounds(for sourceRect: CGRect) -> CGRect {
        guard rotationDegrees != 0 else { return sourceRect }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let corners = [
            CGPoint(x: sourceRect.minX, y: sourceRect.minY),
            CGPoint(x: sourceRect.maxX, y: sourceRect.minY),
            CGPoint(x: sourceRect.maxX, y: sourceRect.maxY),
            CGPoint(x: sourceRect.minX, y: sourceRect.maxY),
        ].map { rotate($0, around: center, by: rotationRadians) }

        let minX = corners.map(\.x).min() ?? sourceRect.minX
        let maxX = corners.map(\.x).max() ?? sourceRect.maxX
        let minY = corners.map(\.y).min() ?? sourceRect.minY
        let maxY = corners.map(\.y).max() ?? sourceRect.maxY
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func rotate(_ point: CGPoint, around center: CGPoint, by angle: CGFloat) -> CGPoint {
        let dx = point.x - center.x
        let dy = point.y - center.y
        return CGPoint(
            x: center.x + (dx * cos(angle)) - (dy * sin(angle)),
            y: center.y + (dx * sin(angle)) + (dy * cos(angle))
        )
    }
}
