import AppKit

final class ArrowAnnotation: Annotation {
    let id = UUID()
    let type: ToolType = .arrow
    var zOrder: Int = 0
    var isVisible: Bool = true

    let start: NSPoint
    let end: NSPoint
    let color: NSColor
    let strokeWidth: CGFloat
    let style: ArrowStyle

    var boundingRect: CGRect {
        CGRect(
            x: min(start.x, end.x) - 10,
            y: min(start.y, end.y) - 10,
            width: abs(end.x - start.x) + 20,
            height: abs(end.y - start.y) + 20
        )
    }

    init(start: NSPoint, end: NSPoint, color: NSColor, strokeWidth: CGFloat, style: ArrowStyle) {
        self.start = start
        self.end = end
        self.color = color
        self.strokeWidth = strokeWidth
        self.style = style
    }

    func render(in context: CGContext) {
        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(strokeWidth)
        context.setLineCap(.round)

        // Draw line
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()

        // Draw arrowhead
        let angle = atan2(end.y - start.y, end.x - start.x)
        let arrowLength: CGFloat = max(strokeWidth * 4, 15)
        let arrowAngle: CGFloat = .pi / 6

        let p1 = CGPoint(
            x: end.x - arrowLength * cos(angle - arrowAngle),
            y: end.y - arrowLength * sin(angle - arrowAngle)
        )
        let p2 = CGPoint(
            x: end.x - arrowLength * cos(angle + arrowAngle),
            y: end.y - arrowLength * sin(angle + arrowAngle)
        )

        context.setFillColor(color.cgColor)
        context.move(to: end)
        context.addLine(to: p1)
        context.addLine(to: p2)
        context.closePath()
        context.fillPath()

        context.restoreGState()
    }
}
