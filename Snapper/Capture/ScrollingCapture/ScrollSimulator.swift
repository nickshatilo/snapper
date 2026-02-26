import AppKit

enum ScrollSimulator {
    static func focus(at point: CGPoint) -> pid_t? {
        let targetPID = windowPID(at: point)

        if
            let targetPID,
            let targetApp = NSRunningApplication(processIdentifier: targetPID),
            targetApp.activate(options: [])
        {
            return targetPID
        }

        // Fallback to a synthetic click if app activation fails.
        guard
            let mouseDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
            let mouseUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
        else { return targetPID }

        mouseDown.post(tap: .cghidEventTap)
        mouseUp.post(tap: .cghidEventTap)
        return targetPID
    }

    @discardableResult
    static func scrollDown(amount: Int, at point: CGPoint, targetPID: pid_t?) -> Bool {
        var posted = false

        if let lineEvent = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 1,
            wheel1: Int32(-max(1, amount)),
            wheel2: 0,
            wheel3: 0
        ) {
            post(lineEvent, at: point, targetPID: targetPID)
            posted = true
        }

        // Some apps react better to pixel-based wheel events.
        if let pixelEvent = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 1,
            wheel1: Int32(-max(1, amount * 40)),
            wheel2: 0,
            wheel3: 0
        ) {
            post(pixelEvent, at: point, targetPID: targetPID)
            posted = true
        }

        return posted
    }

    @discardableResult
    static func scrollUp(amount: Int, at point: CGPoint, targetPID: pid_t?) -> Bool {
        var posted = false

        if let lineEvent = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 1,
            wheel1: Int32(max(1, amount)),
            wheel2: 0,
            wheel3: 0
        ) {
            post(lineEvent, at: point, targetPID: targetPID)
            posted = true
        }

        if let pixelEvent = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 1,
            wheel1: Int32(max(1, amount * 40)),
            wheel2: 0,
            wheel3: 0
        ) {
            post(pixelEvent, at: point, targetPID: targetPID)
            posted = true
        }

        return posted
    }

    @discardableResult
    static func pageDown(targetPID: pid_t?) -> Bool {
        // kVK_PageDown = 121
        guard
            let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 121, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 121, keyDown: false)
        else { return false }

        if let targetPID {
            keyDown.postToPid(targetPID)
            keyUp.postToPid(targetPID)
        } else {
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
        return true
    }

    private static func windowPID(at point: CGPoint) -> pid_t? {
        guard
            let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }

        let currentPID = ProcessInfo.processInfo.processIdentifier

        for info in infoList {
            let ownerName = info[kCGWindowOwnerName as String] as? String ?? ""
            if ownerName == "Window Server" || ownerName == "Dock" {
                continue
            }

            guard
                let ownerPIDNumber = info[kCGWindowOwnerPID as String] as? NSNumber
            else { continue }
            let ownerPID = pid_t(ownerPIDNumber.int32Value)
            if ownerPID == currentPID {
                continue
            }

            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            if layer < 0 {
                continue
            }

            guard
                let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsDict),
                bounds.contains(point)
            else { continue }

            let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1.0
            if alpha <= 0.01 {
                continue
            }

            return ownerPID
        }

        return nil
    }

    private static func post(_ event: CGEvent, at point: CGPoint, targetPID: pid_t?) {
        event.location = point
        if let targetPID {
            event.postToPid(targetPID)
        } else {
            event.post(tap: .cghidEventTap)
        }
    }
}
