import AppKit

final class ArrowAnnotation: Annotation {
    let id: UUID
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

    init(
        id: UUID = UUID(),
        start: NSPoint,
        end: NSPoint,
        color: NSColor,
        strokeWidth: CGFloat,
        style: ArrowStyle
    ) {
        self.id = id
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
        context.setLineJoin(.round)

        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(hypot(dx, dy), 0.001)
        let direction = CGPoint(x: dx / length, y: dy / length)
        let angle = atan2(direction.y, direction.x)
        let arrowLength = headLength
        let arrowAngle: CGFloat = .pi / 6

        let leftHead = CGPoint(
            x: end.x - arrowLength * cos(angle - arrowAngle),
            y: end.y - arrowLength * sin(angle - arrowAngle)
        )
        let rightHead = CGPoint(
            x: end.x - arrowLength * cos(angle + arrowAngle),
            y: end.y - arrowLength * sin(angle + arrowAngle)
        )

        switch style {
        case .straight:
            context.move(to: start)
            context.addLine(to: end)
            context.strokePath()

            context.setFillColor(color.cgColor)
            context.move(to: end)
            context.addLine(to: leftHead)
            context.addLine(to: rightHead)
            context.closePath()
            context.fillPath()

        case .curved:
            let control = curveControlPoint

            context.move(to: start)
            context.addQuadCurve(to: end, control: control)
            context.strokePath()

            let tangent = CGPoint(x: end.x - control.x, y: end.y - control.y)
            let tangentAngle = atan2(tangent.y, tangent.x)
            let curveLeftHead = CGPoint(
                x: end.x - arrowLength * cos(tangentAngle - arrowAngle),
                y: end.y - arrowLength * sin(tangentAngle - arrowAngle)
            )
            let curveRightHead = CGPoint(
                x: end.x - arrowLength * cos(tangentAngle + arrowAngle),
                y: end.y - arrowLength * sin(tangentAngle + arrowAngle)
            )

            context.setFillColor(color.cgColor)
            context.move(to: end)
            context.addLine(to: curveLeftHead)
            context.addLine(to: curveRightHead)
            context.closePath()
            context.fillPath()

        case .tapered:
            let normal = CGPoint(x: -direction.y, y: direction.x)
            let baseWidth = max(strokeWidth * 2.2, 6)
            let neckWidth = max(strokeWidth * 0.55, 1.4)
            let neckOffset = arrowLength * 0.72
            let neck = CGPoint(
                x: end.x - direction.x * neckOffset,
                y: end.y - direction.y * neckOffset
            )

            let p1 = CGPoint(x: start.x + normal.x * baseWidth / 2, y: start.y + normal.y * baseWidth / 2)
            let p2 = CGPoint(x: start.x - normal.x * baseWidth / 2, y: start.y - normal.y * baseWidth / 2)
            let p3 = CGPoint(x: neck.x - normal.x * neckWidth / 2, y: neck.y - normal.y * neckWidth / 2)
            let p4 = CGPoint(x: neck.x + normal.x * neckWidth / 2, y: neck.y + normal.y * neckWidth / 2)

            context.setFillColor(color.cgColor)
            context.move(to: p1)
            context.addLine(to: p2)
            context.addLine(to: p3)
            context.addLine(to: end)
            context.addLine(to: p4)
            context.closePath()
            context.fillPath()

        case .outlined:
            context.move(to: start)
            context.addLine(to: end)
            context.strokePath()

            context.move(to: end)
            context.addLine(to: leftHead)
            context.addLine(to: rightHead)
            context.strokePath()
        }

        context.restoreGState()
    }

    private var headLength: CGFloat { max(strokeWidth * 4, 15) }

    private var curveControlPoint: CGPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(hypot(dx, dy), 0.001)
        let normal = CGPoint(x: -dy / length, y: dx / length)
        let curvature = min(max(length * 0.22, 10), 72)
        return CGPoint(
            x: (start.x + end.x) / 2 + normal.x * curvature,
            y: (start.y + end.y) / 2 + normal.y * curvature
        )
    }

    func hitTest(point: CGPoint) -> Bool {
        let tolerance = AnnotationGeometry.strokeHitTolerance
        // Arrowhead: anything within the head's reach of the tip.
        if hypot(point.x - end.x, point.y - end.y) <= headLength + tolerance {
            return true
        }

        let shaftHalfWidth: CGFloat
        switch style {
        case .tapered:
            shaftHalfWidth = max(strokeWidth * 2.2, 6) / 2
        default:
            shaftHalfWidth = strokeWidth / 2
        }

        let shaft: [CGPoint]
        if style == .curved {
            let control = curveControlPoint
            let samples = 24
            shaft = (0...samples).map { step in
                let t = CGFloat(step) / CGFloat(samples)
                let u: CGFloat = 1 - t
                let a: CGFloat = u * u
                let b: CGFloat = 2 * u * t
                let c: CGFloat = t * t
                let x: CGFloat = a * start.x + b * control.x + c * end.x
                let y: CGFloat = a * start.y + b * control.y + c * end.y
                return CGPoint(x: x, y: y)
            }
        } else {
            shaft = [start, end]
        }
        return AnnotationGeometry.distance(from: point, toPolyline: shaft) <= shaftHalfWidth + tolerance
    }

    func duplicate() -> any Annotation {
        ArrowAnnotation(
            id: id,
            start: start,
            end: end,
            color: color,
            strokeWidth: strokeWidth,
            style: style
        )
    }
}
