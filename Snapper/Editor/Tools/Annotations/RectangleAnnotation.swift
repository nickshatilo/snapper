import AppKit

final class RectangleAnnotation: Annotation {
    let id = UUID()
    let type: ToolType = .rectangle
    var zOrder: Int = 0
    var isVisible: Bool = true

    let rect: CGRect
    let strokeColor: NSColor
    let fillColor: NSColor?
    let strokeWidth: CGFloat
    let cornerRadius: CGFloat

    var boundingRect: CGRect { rect.insetBy(dx: -strokeWidth, dy: -strokeWidth) }

    init(rect: CGRect, strokeColor: NSColor, fillColor: NSColor?, strokeWidth: CGFloat, cornerRadius: CGFloat = 0) {
        self.rect = rect
        self.strokeColor = strokeColor
        self.fillColor = fillColor
        self.strokeWidth = strokeWidth
        self.cornerRadius = cornerRadius
    }

    func render(in context: CGContext) {
        context.saveGState()

        let path: CGPath
        if cornerRadius > 0 {
            path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        } else {
            path = CGPath(rect: rect, transform: nil)
        }

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
}
