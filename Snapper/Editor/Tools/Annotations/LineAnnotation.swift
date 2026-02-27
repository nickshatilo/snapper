import AppKit

final class LineAnnotation: Annotation {
    let id: UUID
    let type: ToolType = .line
    var zOrder: Int = 0
    var isVisible: Bool = true

    let start: NSPoint
    let end: NSPoint
    let color: NSColor
    let strokeWidth: CGFloat
    let isDashed: Bool

    var boundingRect: CGRect {
        CGRect(
            x: min(start.x, end.x) - strokeWidth,
            y: min(start.y, end.y) - strokeWidth,
            width: abs(end.x - start.x) + strokeWidth * 2,
            height: abs(end.y - start.y) + strokeWidth * 2
        )
    }

    init(
        id: UUID = UUID(),
        start: NSPoint,
        end: NSPoint,
        color: NSColor,
        strokeWidth: CGFloat,
        isDashed: Bool = false
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.color = color
        self.strokeWidth = strokeWidth
        self.isDashed = isDashed
    }

    func render(in context: CGContext) {
        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(strokeWidth)
        context.setLineCap(.round)

        if isDashed {
            context.setLineDash(phase: 0, lengths: [8, 6])
        }

        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()
        context.restoreGState()
    }

    func duplicate() -> any Annotation {
        LineAnnotation(
            id: id,
            start: start,
            end: end,
            color: color,
            strokeWidth: strokeWidth,
            isDashed: isDashed
        )
    }
}
