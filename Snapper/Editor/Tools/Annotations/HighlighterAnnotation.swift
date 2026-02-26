import AppKit

final class HighlighterAnnotation: Annotation {
    let id = UUID()
    let type: ToolType = .highlighter
    var zOrder: Int = 0
    var isVisible: Bool = true

    let start: NSPoint
    let end: NSPoint
    let color: NSColor
    let strokeWidth: CGFloat

    var boundingRect: CGRect {
        CGRect(
            x: min(start.x, end.x) - strokeWidth,
            y: min(start.y, end.y) - strokeWidth,
            width: abs(end.x - start.x) + strokeWidth * 2,
            height: abs(end.y - start.y) + strokeWidth * 2
        )
    }

    init(start: NSPoint, end: NSPoint, color: NSColor, strokeWidth: CGFloat) {
        self.start = start
        self.end = end
        self.color = color
        self.strokeWidth = strokeWidth
    }

    func render(in context: CGContext) {
        context.saveGState()
        context.setBlendMode(.multiply)
        context.setStrokeColor(color.withAlphaComponent(0.4).cgColor)
        context.setLineWidth(strokeWidth)
        context.setLineCap(.butt)

        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()
        context.restoreGState()
    }
}
