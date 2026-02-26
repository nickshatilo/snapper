import AppKit

final class TextAnnotation: Annotation {
    let id = UUID()
    let type: ToolType = .text
    var zOrder: Int = 0
    var isVisible: Bool = true

    var position: NSPoint
    var text: String
    var fontName: String
    var fontSize: CGFloat
    var color: NSColor
    var isBold: Bool = false
    var isItalic: Bool = false
    var hasBackground: Bool = false

    var boundingRect: CGRect {
        let attrs = textAttributes
        let size = (text as NSString).size(withAttributes: attrs)
        return CGRect(x: position.x, y: position.y, width: size.width + 8, height: size.height + 4)
    }

    init(position: NSPoint, text: String, fontName: String, fontSize: CGFloat, color: NSColor) {
        self.position = position
        self.text = text
        self.fontName = fontName
        self.fontSize = fontSize
        self.color = color
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

        let attrs = textAttributes
        let attrString = NSAttributedString(string: text, attributes: attrs)
        let size = attrString.size()

        if hasBackground {
            let bgRect = CGRect(x: position.x - 4, y: position.y - 2, width: size.width + 8, height: size.height + 4)
            context.setFillColor(NSColor.black.withAlphaComponent(0.6).cgColor)
            let bgPath = CGPath(roundedRect: bgRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
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
}
