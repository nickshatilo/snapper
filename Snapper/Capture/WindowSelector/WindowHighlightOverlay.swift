import AppKit

final class WindowHighlightOverlay: NSView {
    /// Highlight rect in AppKit's global screen coordinate space.
    var highlightScreenFrame: CGRect?

    private let highlightColor = NSColor.systemBlue.withAlphaComponent(0.3)
    private let borderColor = NSColor.systemBlue
    private let borderWidth: CGFloat = 2.0

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext,
              let screenFrame = highlightScreenFrame,
              let window else { return }

        // ScreenCaptureKit frames are converted to global AppKit coordinates by
        // the controller. Convert once more through this overlay's window so
        // highlights land correctly on every display, not just the primary one.
        let windowFrame = window.convertFromScreen(screenFrame)
        let viewFrame = convert(windowFrame, from: nil).intersection(bounds)
        guard !viewFrame.isNull, !viewFrame.isEmpty else { return }

        context.setFillColor(highlightColor.cgColor)
        context.fill(viewFrame)

        context.setStrokeColor(borderColor.cgColor)
        context.setLineWidth(borderWidth)
        context.stroke(viewFrame.insetBy(dx: borderWidth / 2, dy: borderWidth / 2))
    }
}
