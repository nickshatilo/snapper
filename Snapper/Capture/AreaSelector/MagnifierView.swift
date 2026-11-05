import AppKit

final class MagnifierView: NSView {
    private var capturedImage: CGImage?
    private let magnifierSize: CGFloat = Constants.Defaults.magnifierSize
    private let zoomFactor: CGFloat = Constants.Defaults.magnifierZoom
    private let borderWidth: CGFloat = 2.0

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

    /// Where `capturedImage` lands within `bounds`; smaller than `bounds` when
    /// the sampled area is clipped at a screen edge.
    private var capturedImageRect: CGRect = .zero

    /// Samples around `point` (AppKit global coordinates) from a snapshot of the
    /// screen taken before the selection overlay appeared.
    func update(at point: NSPoint, from display: FrozenScreenSnapshot.Display) {
        let samplePoints = magnifierSize / zoomFactor
        // Snapshot pixels are top-left origin; flip within the display frame.
        let wanted = CGRect(
            x: (point.x - display.frame.minX - samplePoints / 2) * display.scaleX,
            y: (display.frame.maxY - point.y - samplePoints / 2) * display.scaleY,
            width: samplePoints * display.scaleX,
            height: samplePoints * display.scaleY
        )
        let imageBounds = CGRect(x: 0, y: 0, width: display.image.width, height: display.image.height)
        let sampled = wanted.intersection(imageBounds).integral.intersection(imageBounds)

        if sampled.isNull || sampled.isEmpty || wanted.width <= 0 || wanted.height <= 0 {
            capturedImage = nil
        } else {
            capturedImage = display.image.cropping(to: sampled)
            // Map the sampled sub-rect back into view space (y up).
            capturedImageRect = CGRect(
                x: (sampled.minX - wanted.minX) / wanted.width * bounds.width,
                y: (wanted.maxY - sampled.maxY) / wanted.height * bounds.height,
                width: sampled.width / wanted.width * bounds.width,
                height: sampled.height / wanted.height * bounds.height
            )
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext,
              let image = capturedImage else { return }

        context.setFillColor(NSColor.black.cgColor)
        context.fill(bounds)
        context.interpolationQuality = .none
        context.draw(image, in: capturedImageRect)

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
