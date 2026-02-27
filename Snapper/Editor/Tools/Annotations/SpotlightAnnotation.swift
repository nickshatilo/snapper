import AppKit

final class SpotlightAnnotation: Annotation {
    let id: UUID
    let type: ToolType = .spotlight
    var zOrder: Int = 0
    var isVisible: Bool = true

    let rect: CGRect
    let dimOpacity: CGFloat

    var boundingRect: CGRect { .infinite }

    init(id: UUID = UUID(), rect: CGRect, dimOpacity: CGFloat) {
        self.id = id
        self.rect = rect
        self.dimOpacity = dimOpacity
    }

    func render(in context: CGContext) {
        context.saveGState()

        // Get canvas bounds from the clip bounding box
        let canvasBounds = context.boundingBoxOfClipPath

        // Draw dark overlay over everything
        context.setFillColor(NSColor.black.withAlphaComponent(dimOpacity).cgColor)
        context.fill(canvasBounds)

        // Clear the spotlight area
        context.setBlendMode(.clear)
        context.fill(rect)
        context.setBlendMode(.normal)

        context.restoreGState()
    }

    func hitTest(point: CGPoint) -> Bool {
        rect.contains(point)
    }

    func duplicate() -> any Annotation {
        SpotlightAnnotation(
            id: id,
            rect: rect,
            dimOpacity: dimOpacity
        )
    }
}
