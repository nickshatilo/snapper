import AppKit

/// Conversions between AppKit global screen coordinates (origin at the
/// bottom-left of the primary screen, y up) and CG/Quartz global coordinates
/// (origin at the top-left of the primary screen, y down) — the space used by
/// ScreenCaptureKit, CGWindowList, Accessibility, and CGEvent.
///
/// The two spaces only coincide on rects that are vertically symmetric within
/// the primary screen, which is why mixing them "works" in casual testing and
/// breaks everywhere else. The flip axis is the primary screen's AppKit maxY,
/// and the conversion is its own inverse.
enum CoordinateSpace {
    /// Height of the primary (menu-bar) display, i.e. `NSScreen.screens.first`'s
    /// maxY. Read via CoreGraphics so it is safe from background tasks.
    static var primaryScreenMaxY: CGFloat {
        CGDisplayBounds(CGMainDisplayID()).maxY
    }

    static func appKitToCG(_ rect: CGRect, primaryScreenMaxY: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX,
            y: primaryScreenMaxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    static func appKitToCG(_ point: CGPoint, primaryScreenMaxY: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenMaxY - point.y)
    }

    static func appKitToCG(_ rect: CGRect) -> CGRect {
        appKitToCG(rect, primaryScreenMaxY: primaryScreenMaxY)
    }

    static func appKitToCG(_ point: CGPoint) -> CGPoint {
        appKitToCG(point, primaryScreenMaxY: primaryScreenMaxY)
    }

    static func cgToAppKit(_ rect: CGRect) -> CGRect {
        appKitToCG(rect)
    }

    static func cgToAppKit(_ point: CGPoint) -> CGPoint {
        appKitToCG(point)
    }
}
