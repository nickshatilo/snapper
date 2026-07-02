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
    private let eventSource = CGEventSource(stateID: .hidSystemState)

    /// Scroll magnitude, adapted after each observed shift so a step moves
    /// roughly `targetShiftRatio` of the capture region.
    /// AX path: fraction of the scrollbar range. Event path: points per wheel event.
    private var axStepFraction: Double = 0.02
    private var eventStepPoints: Double
    private let targetShiftRatio = 0.3

    init(target: Target, regionHeightPoints: CGFloat) {
        self.target = target
        self.eventStepPoints = min(max(Double(regionHeightPoints) * targetShiftRatio, 30), 120)
    }

    var targetName: String? {
        target.appName
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

        if case let .event(point, _, _) = target {
            movePointer(to: point)
        }
    }

    func requestNextStep() -> StepResult {
        switch target {
        case let .accessibility(scrollBar, _, _):
            return requestAXScrollStep(scrollBar: scrollBar)
        case let .event(point, _, _):
            movePointer(to: point)
            postScrollEvent(at: point)
            return .requested
        }
    }

    /// Feeds back the pixel shift the estimator actually observed so the next
    /// step lands near the target ratio — small enough for reliable overlap
    /// detection, large enough to make progress.
    func adaptStep(observedShift: Int, regionHeight: Int) {
        guard observedShift > 0, regionHeight > 0 else { return }
        let targetShift = Double(regionHeight) * targetShiftRatio
        let ratio = min(max(targetShift / Double(observedShift), 0.5), 2.0)

        switch target {
        case .accessibility:
            axStepFraction = min(max(axStepFraction * ratio, 0.005), 0.25)
        case .event:
            eventStepPoints = min(max(eventStepPoints * ratio, 20), 150)
        }
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
