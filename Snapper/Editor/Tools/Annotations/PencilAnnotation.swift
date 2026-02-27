import AppKit

final class PencilAnnotation: Annotation {
    let id: UUID
    let type: ToolType = .pencil
    var zOrder: Int = 0
    var isVisible: Bool = true

    let points: [NSPoint]
    let color: NSColor
    let strokeWidth: CGFloat

    var boundingRect: CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, maxX = first.x
        var minY = first.y, maxY = first.y
        for p in points {
            minX = min(minX, p.x)
            maxX = max(maxX, p.x)
            minY = min(minY, p.y)
            maxY = max(maxY, p.y)
        }
        return CGRect(x: minX - strokeWidth, y: minY - strokeWidth,
                       width: maxX - minX + strokeWidth * 2,
                       height: maxY - minY + strokeWidth * 2)
    }

    init(id: UUID = UUID(), points: [NSPoint], color: NSColor, strokeWidth: CGFloat) {
        self.id = id
        self.points = points
        self.color = color
        self.strokeWidth = strokeWidth
    }

    func render(in context: CGContext) {
        guard points.count >= 2 else { return }

        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(strokeWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        // Catmull-Rom spline smoothing
        let smoothed = catmullRomSmooth(points)
        context.move(to: smoothed[0])
        for i in 1..<smoothed.count {
            context.addLine(to: smoothed[i])
        }
        context.strokePath()
        context.restoreGState()
    }

    private func catmullRomSmooth(_ pts: [NSPoint]) -> [NSPoint] {
        guard pts.count >= 4 else { return pts }
        var result: [NSPoint] = [pts[0]]

        for i in 0..<pts.count - 1 {
            let p0 = pts[max(0, i - 1)]
            let p1 = pts[i]
            let p2 = pts[min(pts.count - 1, i + 1)]
            let p3 = pts[min(pts.count - 1, i + 2)]

            let steps = 4
            for step in 1...steps {
                let t = CGFloat(step) / CGFloat(steps)
                let t2 = t * t
                let t3 = t2 * t

                let x = 0.5 * ((2 * p1.x) +
                    (-p0.x + p2.x) * t +
                    (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2 +
                    (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3)

                let y = 0.5 * ((2 * p1.y) +
                    (-p0.y + p2.y) * t +
                    (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2 +
                    (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3)

                result.append(NSPoint(x: x, y: y))
            }
        }
        return result
    }

    func duplicate() -> any Annotation {
        PencilAnnotation(
            id: id,
            points: points,
            color: color,
            strokeWidth: strokeWidth
        )
    }
}
