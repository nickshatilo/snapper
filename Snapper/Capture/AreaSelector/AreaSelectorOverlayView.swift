import AppKit

final class AreaSelectorOverlayView: NSView {
    var frozenImage: CGImage?
    var showsMagnifier = false

    private var selectionRect: NSRect?
    private var selectionPixelSize: CGSize?
    private var magnifierView: MagnifierView?

    private let overlayColor = NSColor.black.withAlphaComponent(0.3)
    private let selectionBorderColor = NSColor.white
    private let dimensionFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
    private let magnifierInset: CGFloat = 16

    override var acceptsFirstResponder: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        if let frozenImage {
            context.draw(frozenImage, in: bounds)
        }

        if let rect = selectionRect {
            // Only dim the screen once selection starts so users can see the target content clearly.
            context.setFillColor(overlayColor.cgColor)
            context.fill(bounds)

            // Clear the selection area
            if frozenImage != nil {
                context.saveGState()
                context.clip(to: rect)
                if let frozenImage {
                    context.draw(frozenImage, in: bounds)
                }
                context.restoreGState()
            } else {
                context.clear(rect)
            }

            // Dashed border
            context.setStrokeColor(selectionBorderColor.cgColor)
            context.setLineWidth(1.0)
            context.setLineDash(phase: 0, lengths: [6, 4])
            context.stroke(rect)

            // Dimension label
            drawDimensionLabel(context: context, rect: rect)
        }

    }

    private func drawDimensionLabel(context: CGContext, rect: CGRect) {
        let scale = window?.backingScaleFactor ?? 2.0
        let w: Int
        let h: Int
        if let selectionPixelSize {
            w = Int(selectionPixelSize.width.rounded())
            h = Int(selectionPixelSize.height.rounded())
        } else {
            w = Int(rect.width * scale)
            h = Int(rect.height * scale)
        }
        let text = "\(w) × \(h)"

        let attrs: [NSAttributedString.Key: Any] = [
            .font: dimensionFont,
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attrs)

        // Position below selection rect
        let labelX = rect.midX - size.width / 2
        let labelY = rect.minY - size.height - 8

        let bgRect = NSRect(x: labelX - 6, y: labelY - 2, width: size.width + 12, height: size.height + 4)
        context.setFillColor(NSColor.black.withAlphaComponent(0.7).cgColor)
        let bgPath = CGPath(roundedRect: bgRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
        context.addPath(bgPath)
        context.fillPath()

        (text as NSString).draw(at: NSPoint(x: labelX, y: labelY), withAttributes: attrs)
    }

    @discardableResult
    func clearSelection() -> Bool {
        let hadSelection = selectionRect != nil
        selectionRect = nil
        selectionPixelSize = nil
        if hadSelection {
            needsDisplay = true
        }
        return hadSelection
    }

    func setSelectionRect(_ rect: CGRect?, pixelSize: CGSize?) {
        let nextRect = rect
        guard selectionRect != nextRect || selectionPixelSize != pixelSize else { return }
        selectionRect = nextRect
        selectionPixelSize = pixelSize
        needsDisplay = true
    }

    func setMagnifierPointInScreen(_ point: NSPoint?) {
        guard let point else {
            magnifierView?.isHidden = true
            return
        }
        updateMagnifier(atScreenPoint: point)
    }

    private func updateMagnifier(atScreenPoint screenPoint: NSPoint) {
        guard showsMagnifier, let window else {
            magnifierView?.isHidden = true
            return
        }

        let magnifier = ensureMagnifierView()
        let point = NSPoint(
            x: screenPoint.x - window.frame.origin.x,
            y: screenPoint.y - window.frame.origin.y
        )

        if let screen = window.screen {
            magnifier.update(at: screenPoint, on: screen)
        }
        magnifier.isHidden = false

        var frame = magnifier.frame
        frame.origin = NSPoint(
            x: point.x + magnifierInset,
            y: point.y + magnifierInset
        )
        if frame.maxX > bounds.maxX {
            frame.origin.x = point.x - magnifierInset - frame.width
        }
        if frame.maxY > bounds.maxY {
            frame.origin.y = point.y - magnifierInset - frame.height
        }
        frame.origin.x = max(bounds.minX, min(frame.origin.x, bounds.maxX - frame.width))
        frame.origin.y = max(bounds.minY, min(frame.origin.y, bounds.maxY - frame.height))
        magnifier.frame = frame
    }

    private func ensureMagnifierView() -> MagnifierView {
        if let magnifierView {
            return magnifierView
        }
        let magnifier = MagnifierView(frame: .zero)
        magnifier.isHidden = true
        addSubview(magnifier)
        magnifierView = magnifier
        return magnifier
    }
}
