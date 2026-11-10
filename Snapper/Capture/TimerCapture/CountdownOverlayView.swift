import AppKit

final class CountdownOverlayView: NSView {
    private var countdown: Int = 3
    private var total: Int = 3
    private let font = NSFont.monospacedSystemFont(ofSize: 120, weight: .bold)

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Semi-transparent background
        context.setFillColor(NSColor.black.withAlphaComponent(0.3).cgColor)
        context.fill(bounds)

        // Draw number
        let text = "\(countdown)"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let point = NSPoint(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2
        )

        // Draw circular progress behind the number
        let radius: CGFloat = 80
        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        // Background circle
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.3).cgColor)
        context.setLineWidth(4)
        context.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        context.strokePath()

        // Remaining time, as the part of the ring that is left. The view is
        // not flipped, so .pi / 2 is 12 o'clock and the arc shrinks clockwise.
        let fraction = min(1, max(0, CGFloat(countdown) / CGFloat(total)))
        if fraction > 0 {
            context.setStrokeColor(NSColor.white.cgColor)
            context.setLineWidth(4)
            context.setLineCap(.round)
            let startAngle: CGFloat = .pi / 2
            if fraction >= 1 {
                context.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
            } else {
                let endAngle = startAngle - .pi * 2 * fraction
                context.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
            }
            context.strokePath()
        }

        (text as NSString).draw(at: point, withAttributes: attrs)
    }

    func setCountdown(_ value: Int, total: Int) {
        countdown = value
        // Guards the division in draw(_:).
        self.total = max(1, total)
        needsDisplay = true
    }
}
