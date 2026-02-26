import AppKit

final class MagnifierView: NSView {
    private var capturedImage: CGImage?
    private let magnifierSize: CGFloat = Constants.Defaults.magnifierSize
    private let zoomFactor: CGFloat = Constants.Defaults.magnifierZoom
    private let borderWidth: CGFloat = 2.0

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: magnifierSize, height: magnifierSize))
        wantsLayer = true
        layer?.cornerRadius = magnifierSize / 2
        layer?.masksToBounds = true
        layer?.borderWidth = borderWidth
        layer?.borderColor = NSColor.white.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    func update(at point: NSPoint, on screen: NSScreen) {
        let captureSize = magnifierSize / zoomFactor
        let captureRect = CGRect(
            x: point.x - captureSize / 2,
            y: point.y - captureSize / 2,
            width: captureSize,
            height: captureSize
        )

        capturedImage = CGWindowListCreateImage(
            captureRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        )
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext,
              let image = capturedImage else { return }

        context.interpolationQuality = .none
        context.draw(image, in: bounds)

        // Crosshair at center
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        context.setStrokeColor(NSColor.red.withAlphaComponent(0.8).cgColor)
        context.setLineWidth(0.5)

        context.move(to: CGPoint(x: center.x - 10, y: center.y))
        context.addLine(to: CGPoint(x: center.x + 10, y: center.y))
        context.strokePath()

        context.move(to: CGPoint(x: center.x, y: center.y - 10))
        context.addLine(to: CGPoint(x: center.x, y: center.y + 10))
        context.strokePath()
    }
}
