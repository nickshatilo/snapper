import AppKit

final class AreaSelectorOverlayView: NSView {
    var onSelectionComplete: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private var selectionStart: NSPoint?
    private var selectionRect: NSRect?
    private var isDragging = false

    private let overlayColor = NSColor.black.withAlphaComponent(0.3)
    private let selectionBorderColor = NSColor.white
    private let dimensionFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)

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

        // Dark overlay
        context.setFillColor(overlayColor.cgColor)
        context.fill(bounds)

        if let rect = selectionRect {
            // Clear the selection area
            context.clear(rect)

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
        let w = Int(rect.width * scale)
        let h = Int(rect.height * scale)
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

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        selectionStart = point
        selectionRect = nil
        isDragging = true
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = selectionStart else { return }
        let current = convert(event.locationInWindow, from: nil)
        selectionRect = NSRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        if let rect = selectionRect, rect.width > 5 && rect.height > 5 {
            onSelectionComplete?(rect)
        } else {
            selectionRect = nil
            needsDisplay = true
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            selectionStart = nil
            selectionRect = nil
            isDragging = false
            needsDisplay = true
            onCancel?()
            return
        }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        selectionStart = nil
        selectionRect = nil
        isDragging = false
        needsDisplay = true
        onCancel?()
    }
}
