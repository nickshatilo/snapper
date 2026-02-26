import AppKit

final class WindowHighlightOverlay: NSView {
    var highlightFrame: CGRect?

    private let highlightColor = NSColor.systemBlue.withAlphaComponent(0.3)
    private let borderColor = NSColor.systemBlue
    private let borderWidth: CGFloat = 2.0

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext,
              let frame = highlightFrame else { return }

        // Convert screen coordinates to view coordinates
        let viewFrame = convert(frame, from: nil)

        context.setFillColor(highlightColor.cgColor)
        context.fill(viewFrame)

        context.setStrokeColor(borderColor.cgColor)
        context.setLineWidth(borderWidth)
        context.stroke(viewFrame.insetBy(dx: borderWidth / 2, dy: borderWidth / 2))
    }
}
