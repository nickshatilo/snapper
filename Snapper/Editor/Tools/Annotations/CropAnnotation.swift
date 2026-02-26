import AppKit

final class CropAnnotation: Annotation {
    let id = UUID()
    let type: ToolType = .crop
    var zOrder: Int = 999
    var isVisible: Bool = true

    var rect: CGRect

    var boundingRect: CGRect { rect }

    init(rect: CGRect) {
        self.rect = rect
    }

    func render(in context: CGContext) {
        context.saveGState()

        // Dim outside crop area
        let canvasBounds = context.boundingBoxOfClipPath
        context.setFillColor(NSColor.black.withAlphaComponent(0.5).cgColor)

        // Fill entire canvas
        context.fill(canvasBounds)
        // Clear crop area
        context.setBlendMode(.clear)
        context.fill(rect)
        context.setBlendMode(.normal)

        // Draw crop border
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(1.5)
        context.stroke(rect)

        // Draw rule-of-thirds grid
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.4).cgColor)
        context.setLineWidth(0.5)

        let thirdW = rect.width / 3
        let thirdH = rect.height / 3

        for i in 1...2 {
            // Vertical lines
            let x = rect.origin.x + thirdW * CGFloat(i)
            context.move(to: CGPoint(x: x, y: rect.minY))
            context.addLine(to: CGPoint(x: x, y: rect.maxY))
            context.strokePath()

            // Horizontal lines
            let y = rect.origin.y + thirdH * CGFloat(i)
            context.move(to: CGPoint(x: rect.minX, y: y))
            context.addLine(to: CGPoint(x: rect.maxX, y: y))
            context.strokePath()
        }

        // Draw corner handles
        let handleSize: CGFloat = 8
        context.setFillColor(NSColor.white.cgColor)
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY),
        ]
        for corner in corners {
            let handleRect = CGRect(
                x: corner.x - handleSize / 2,
                y: corner.y - handleSize / 2,
                width: handleSize,
                height: handleSize
            )
            context.fill(handleRect)
        }

        context.restoreGState()
    }
}
