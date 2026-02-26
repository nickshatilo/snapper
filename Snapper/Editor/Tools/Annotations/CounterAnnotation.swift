import AppKit

final class CounterAnnotation: Annotation {
    let id = UUID()
    let type: ToolType = .counter
    var zOrder: Int = 0
    var isVisible: Bool = true

    let position: NSPoint
    var value: Int
    let style: CounterStyle
    let color: NSColor
    let radius: CGFloat = 16

    var boundingRect: CGRect {
        CGRect(x: position.x - radius, y: position.y - radius, width: radius * 2, height: radius * 2)
    }

    init(position: NSPoint, value: Int, style: CounterStyle, color: NSColor) {
        self.position = position
        self.value = value
        self.style = style
        self.color = color
    }

    func render(in context: CGContext) {
        context.saveGState()

        // Draw circle
        let circleRect = CGRect(x: position.x - radius, y: position.y - radius, width: radius * 2, height: radius * 2)
        context.setFillColor(color.cgColor)
        context.fillEllipse(in: circleRect)

        // Draw text
        let text = style.display(for: value)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: radius, weight: .bold),
            .foregroundColor: NSColor.white,
        ]

        let attrString = NSAttributedString(string: text, attributes: attrs)
        let textSize = attrString.size()

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        attrString.draw(at: NSPoint(
            x: position.x - textSize.width / 2,
            y: position.y - textSize.height / 2
        ))
        NSGraphicsContext.restoreGraphicsState()

        context.restoreGState()
    }
}
