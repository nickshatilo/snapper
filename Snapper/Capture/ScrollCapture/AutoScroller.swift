import AppKit
import ApplicationServices
import ScreenCaptureKit

/// Drives downward scrolling of the content under a point.
/// All points are CG top-left global coordinates (the space shared by
/// `SCWindow.frame`, `AXUIElementCopyElementAtPosition`, and `CGEvent`).
final class AutoScroller {
    enum StepResult {
        case requested
        case reachedEnd
        /// Wheel path only: the pointer is outside the capture region (the
        /// user took it, e.g. toward Stop). Nothing was posted; try again
        /// once it returns.
        case paused
    }

    enum Target {
        case accessibility(
            scrollBar: AXUIElement,
            appPID: pid_t?,
            appName: String?
        )
        case event(
            point: CGPoint,
            appPID: pid_t?,
            appName: String?
        )

        var appPID: pid_t? {
            switch self {
            case let .accessibility(_, appPID, _):
                return appPID
            case let .event(_, appPID, _):
                return appPID
            }
        }

        var appName: String? {
            switch self {
            case let .accessibility(_, _, appName):
                return appName
            case let .event(_, _, appName):
                return appName
            }
        }
    }

    private let target: Target
    /// Capture region, CG top-left global points.
    private let region: CGRect
    private let eventSource = CGEventSource(stateID: .hidSystemState)

    /// Scroll magnitude, adapted after each observed shift so a step moves
    /// roughly `targetShiftRatio` of the capture region.
    /// AX path: fraction of the scrollbar range. Event path: points per wheel event.
    private var axStepFraction: Double = 0.02
    private var eventStepPoints: Double
    private let targetShiftRatio = 0.3
    private let axStepFractionRange = 0.0002...0.25
    private let eventStepPointsRange = 20.0...150.0

    /// Scroll bar value at the last frame the stitcher accepted, so an
    /// unverifiable (overshooting) AX step can be rewound.
    private var acceptedAXValue: Double?

    init(target: Target, region: CGRect) {
        self.target = target
        self.region = region
        self.eventStepPoints = min(max(Double(region.height) * targetShiftRatio, 30), 120)
    }

    var targetName: String? {
        target.appName
    }

    /// Wheel-event targets have no end-of-content signal; the caller infers
    /// the end from the content no longer moving.
    var usesWheelEvents: Bool {
        if case .event = target { return true }
        return false
    }

    static func resolveTarget(
        at point: CGPoint,
        content: SCShareableContent
    ) -> Target {
        let window = topmostWindow(at: point, content: content)
        let appPID = window.flatMap { $0.owningApplication?.processID }.map { pid_t($0) }
        let appName = window?.owningApplication?.applicationName

        guard PermissionChecker.isAccessibilityGranted(),
              let appPID else {
            return .event(point: point, appPID: appPID, appName: appName)
        }

        let applicationElement = AXUIElementCreateApplication(appPID)
        var hitElement: AXUIElement?
        let hitResult = AXUIElementCopyElementAtPosition(
            applicationElement,
            Float(point.x),
            Float(point.y),
            &hitElement
        )

        guard hitResult == .success,
              let hitElement,
              let scrollBar = findVerticalScrollBar(startingAt: hitElement) else {
            return .event(point: point, appPID: appPID, appName: appName)
        }

        var isSettable = DarwinBoolean(false)
        let settableResult = AXUIElementIsAttributeSettable(
            scrollBar,
            kAXValueAttribute as CFString,
            &isSettable
        )
        guard settableResult == .success, isSettable.boolValue else {
            return .event(point: point, appPID: appPID, appName: appName)
        }

        return .accessibility(scrollBar: scrollBar, appPID: appPID, appName: appName)
    }

    /// Frontmost normal-level window under the point, excluding Snapper's own
    /// windows (e.g. the floating Stop panel). `SCShareableContent.windows`
    /// has no guaranteed z-order, so front-to-back order comes from
    /// CGWindowList and is mapped back by windowID.
    private static func topmostWindow(at point: CGPoint, content: SCShareableContent) -> SCWindow? {
        let ownPID = pid_t(ProcessInfo.processInfo.processIdentifier)

        if let windowInfo = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] {
            for entry in windowInfo {
                guard let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                      pid != ownPID,
                      let layer = entry[kCGWindowLayer as String] as? Int,
                      layer == 0,
                      let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                      let bounds = CGRect(dictionaryRepresentation: boundsDict),
                      bounds.contains(point),
                      let windowID = entry[kCGWindowNumber as String] as? CGWindowID else {
                    continue
                }
                if let match = content.windows.first(where: { $0.windowID == windowID }) {
                    return match
                }
            }
        }

        return content.windows.first(where: { window in
            window.frame.contains(point)
                && window.owningApplication.map { pid_t($0.processID) != ownPID } ?? true
        })
    }

    func prepareForScrolling() {
        if let appPID = target.appPID,
           let application = NSRunningApplication(processIdentifier: appPID) {
            application.activate(options: [.activateAllWindows])
        }

        switch target {
        case let .event(point, _, _):
            // Park the pointer over the target once so HID-routed wheel events
            // reach it. Steps never move it again; see `requestNextStep`.
            movePointer(to: point)
        case let .accessibility(scrollBar, _, _):
            acceptedAXValue = copyNumberAttribute(kAXValueAttribute as CFString, from: scrollBar)
            if let fraction = initialAXStepFraction(scrollBar: scrollBar) {
                axStepFraction = fraction
            }
        }
    }

    func requestNextStep() -> StepResult {
        switch target {
        case let .accessibility(scrollBar, _, _):
            return requestAXScrollStep(scrollBar: scrollBar)
        case let .event(point, _, _):
            // HID-tap wheel events go to the window under the pointer. If the
            // user has moved it off the region, don't yank it back (that made
            // Stop unclickable) and don't scroll whatever it is over: pause.
            guard let pointer = CGEvent(source: nil)?.location, region.contains(pointer) else {
                return .paused
            }
            postScrollEvent(at: point)
            return .requested
        }
    }

    /// Feeds back the pixel shift the estimator actually observed (for the
    /// frame the stitcher accepted) so the next step lands near the target
    /// ratio — small enough for reliable overlap detection, large enough to
    /// make progress.
    func adaptStep(observedShift: Int, regionHeight: Int) {
        guard observedShift > 0, regionHeight > 0 else { return }
        let targetShift = Double(regionHeight) * targetShiftRatio
        let ratio = min(max(targetShift / Double(observedShift), 0.5), 2.0)

        switch target {
        case let .accessibility(scrollBar, _, _):
            axStepFraction = clamp(axStepFraction * ratio, to: axStepFractionRange)
            acceptedAXValue = copyNumberAttribute(kAXValueAttribute as CFString, from: scrollBar)
        case .event:
            eventStepPoints = clamp(eventStepPoints * ratio, to: eventStepPointsRange)
        }
    }

    /// The last step changed the content in a way the estimator couldn't
    /// verify — most likely it overshot the overlap window. Halve the step
    /// and, on the AX path, rewind to the last verified scroll position so
    /// the retry is measured from known content instead of skipping past it.
    func stepFailed() {
        switch target {
        case let .accessibility(scrollBar, _, _):
            axStepFraction = clamp(axStepFraction * 0.5, to: axStepFractionRange)
            if let acceptedAXValue {
                _ = AXUIElementSetAttributeValue(
                    scrollBar,
                    kAXValueAttribute as CFString,
                    NSNumber(value: acceptedAXValue)
                )
            }
        case .event:
            eventStepPoints = clamp(eventStepPoints * 0.5, to: eventStepPointsRange)
        }
    }

    /// An AX step left the content visibly unchanged: the step was too small
    /// to register, so grow it.
    func stepProducedNoMotion() {
        if case .accessibility = target {
            axStepFraction = clamp(axStepFraction * 2, to: axStepFractionRange)
        }
    }

    /// AX scroll bar values span the scrollable distance (content minus
    /// viewport), so a fixed fraction of that range is wildly different on a
    /// short note and a 300-page PDF. Derive the step from the visible
    /// fraction (thumb / track) instead, so it moves ~`targetShiftRatio` of
    /// the capture region regardless of document length.
    private func initialAXStepFraction(scrollBar: AXUIElement) -> Double? {
        guard let trackHeight = Self.copySizeAttribute(from: scrollBar)?.height,
              trackHeight > 0,
              let indicator = Self.copyChildren(of: scrollBar).first(where: {
                  Self.copyStringAttribute(kAXRoleAttribute as CFString, from: $0) == (kAXValueIndicatorRole as String)
              }),
              let thumbHeight = Self.copySizeAttribute(from: indicator)?.height,
              thumbHeight > 0 else {
            return nil
        }

        let visibleFraction = Double(thumbHeight / trackHeight)
        guard visibleFraction > 0, visibleFraction < 0.98 else { return nil }

        // Viewport ≈ track height; scrollable distance = viewport * (1 - r) / r.
        let scrollablePoints = Double(trackHeight) * (1 - visibleFraction) / visibleFraction
        let targetPoints = Double(region.height) * targetShiftRatio
        return clamp(targetPoints / scrollablePoints, to: axStepFractionRange)
    }

    private func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private func requestAXScrollStep(scrollBar: AXUIElement) -> StepResult {
        guard let currentValue = copyNumberAttribute(kAXValueAttribute as CFString, from: scrollBar),
              let minValue = copyNumberAttribute(kAXMinValueAttribute as CFString, from: scrollBar),
              let maxValue = copyNumberAttribute(kAXMaxValueAttribute as CFString, from: scrollBar) else {
            return .requested
        }

        let range = max(0.0001, maxValue - minValue)
        if currentValue >= maxValue - 0.001 {
            return .reachedEnd
        }

        let newValue = min(maxValue, currentValue + (range * axStepFraction))
        let number = NSNumber(value: newValue)
        _ = AXUIElementSetAttributeValue(
            scrollBar,
            kAXValueAttribute as CFString,
            number
        )

        return .requested
    }

    private func movePointer(to point: CGPoint) {
        guard let event = CGEvent(
            mouseEventSource: eventSource,
            mouseType: .mouseMoved,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else {
            return
        }
        event.post(tap: CGEventTapLocation.cghidEventTap)
    }

    /// Posts one wheel step without moving the pointer; callers ensure the
    /// pointer is over the capture region.
    private func postScrollEvent(at point: CGPoint) {
        // Negative wheel1 scrolls the page down (content moves up), which is
        // the direction the motion estimator and stitcher are built for.
        guard let event = CGEvent(
            scrollWheelEvent2Source: eventSource,
            units: .pixel,
            wheelCount: 1,
            wheel1: -Int32(eventStepPoints.rounded()),
            wheel2: 0,
            wheel3: 0
        ) else {
            return
        }

        event.location = point
        event.post(tap: CGEventTapLocation.cghidEventTap)
    }

    private static func findVerticalScrollBar(startingAt element: AXUIElement) -> AXUIElement? {
        var current: AXUIElement? = element

        for _ in 0..<10 {
            guard let resolvedCurrent = current else { break }

            if let scrollBar = copyElementAttribute(kAXVerticalScrollBarAttribute as CFString, from: resolvedCurrent) {
                return scrollBar
            }

            current = copyElementAttribute(kAXParentAttribute as CFString, from: resolvedCurrent)
        }

        return nil
    }

    private static func copyElementAttribute(_ attribute: CFString, from element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private static func copyChildren(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let children = value as? [AXUIElement] else {
            return []
        }
        return children
    }

    private static func copyStringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private static func copySizeAttribute(from element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        var size = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(value, to: AXValue.self), .cgSize, &size) else {
            return nil
        }
        return size
    }

    private func copyNumberAttribute(_ attribute: CFString, from element: AXUIElement) -> Double? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success else {
            return nil
        }

        if let number = value as? NSNumber {
            return number.doubleValue
        }
        return nil
    }
}
