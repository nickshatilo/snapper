import AppKit

final class EllipseAnnotation: Annotation {
    let id = UUID()
    let type: ToolType = .ellipse
    var zOrder: Int = 0
    var isVisible: Bool = true

    let rect: CGRect
    let strokeColor: NSColor
    let fillColor: NSColor?
    let strokeWidth: CGFloat

    var boundingRect: CGRect { rect.insetBy(dx: -strokeWidth, dy: -strokeWidth) }

    init(rect: CGRect, strokeColor: NSColor, fillColor: NSColor?, strokeWidth: CGFloat) {
        self.rect = rect
        self.strokeColor = strokeColor
        self.fillColor = fillColor
        self.strokeWidth = strokeWidth
    }

    func render(in context: CGContext) {
        context.saveGState()

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
}
