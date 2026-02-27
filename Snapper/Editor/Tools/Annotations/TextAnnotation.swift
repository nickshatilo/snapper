import AppKit

final class TextAnnotation: Annotation {
    let id: UUID
    let type: ToolType = .text
    var zOrder: Int = 0
    var isVisible: Bool = true

    var position: NSPoint
    var text: String
    var fontName: String
    var fontSize: CGFloat
    var color: NSColor
    var rotationDegrees: CGFloat
    var isBold: Bool = false
    var isItalic: Bool = false
    var hasBackground: Bool = false

    var boundingRect: CGRect {
        rotatedBounds(for: textContainerRect)
    }

    init(
        id: UUID = UUID(),
        position: NSPoint,
        text: String,
        fontName: String,
        fontSize: CGFloat,
        color: NSColor,
        rotationDegrees: CGFloat = 0
    ) {
        self.id = id
        self.position = position
        self.text = text
        self.fontName = fontName
        self.fontSize = fontSize
        self.color = color
        self.rotationDegrees = rotationDegrees
    }

    private var textAttributes: [NSAttributedString.Key: Any] {
        var font = NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        var traits = NSFontTraitMask()
        if isBold { traits.insert(.boldFontMask) }
        if isItalic { traits.insert(.italicFontMask) }
        if !traits.isEmpty {
            font = NSFontManager.shared.convert(font, toHaveTrait: traits)
        }
        return [
            .font: font,
            .foregroundColor: color,
        ]
    }

    func render(in context: CGContext) {
        context.saveGState()
        let containerRect = textContainerRect
        let center = CGPoint(x: containerRect.midX, y: containerRect.midY)
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: rotationRadians)
        context.translateBy(x: -center.x, y: -center.y)

        let attrs = textAttributes
        let attrString = NSAttributedString(string: text, attributes: attrs)

        if hasBackground {
            context.setFillColor(NSColor.black.withAlphaComponent(0.6).cgColor)
            let bgPath = CGPath(roundedRect: containerRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
            context.addPath(bgPath)
            context.fillPath()
        }

        // Use NSGraphicsContext for text drawing
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        attrString.draw(at: position)
        NSGraphicsContext.restoreGraphicsState()

        context.restoreGState()
    }

    func hitTest(point: CGPoint) -> Bool {
        let center = CGPoint(x: textContainerRect.midX, y: textContainerRect.midY)
        let transformedPoint = rotate(point, around: center, by: -rotationRadians)
        return textContainerRect.insetBy(dx: -2, dy: -2).contains(transformedPoint)
    }

    func duplicate() -> any Annotation {
        let copy = TextAnnotation(
            id: id,
            position: position,
            text: text,
            fontName: fontName,
            fontSize: fontSize,
            color: color,
            rotationDegrees: rotationDegrees
        )
        copy.zOrder = zOrder
        copy.isVisible = isVisible
        copy.isBold = isBold
        copy.isItalic = isItalic
        copy.hasBackground = hasBackground
        return copy
    }

    private var textContainerRect: CGRect {
        let measuredBounds = textMeasuredBounds
        let paddingX: CGFloat = 4
        let paddingY: CGFloat = 2
        return CGRect(
            x: position.x + measuredBounds.minX - paddingX,
            y: position.y + measuredBounds.minY - paddingY,
            width: measuredBounds.width + (paddingX * 2),
            height: measuredBounds.height + (paddingY * 2)
        )
    }

    private var textMeasuredBounds: CGRect {
        let attributed = NSAttributedString(string: text, attributes: textAttributes)
        var bounds = attributed.boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).standardized

        // Keep interaction bounds stable even for very small fonts / short strings.
        if bounds.width < 1 {
            bounds.size.width = max(fontSize * 0.5, 1)
        }
        if bounds.height < 1 {
            bounds.size.height = max(fontSize, 1)
        }
        return bounds
    }

    private var rotationRadians: CGFloat {
        rotationDegrees * (.pi / 180)
    }

    private func rotatedBounds(for sourceRect: CGRect) -> CGRect {
        guard rotationDegrees != 0 else { return sourceRect }
        let center = CGPoint(x: sourceRect.midX, y: sourceRect.midY)
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
