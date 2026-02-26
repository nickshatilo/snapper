import AppKit

enum ScrollSimulator {
    static func scrollDown(amount: Int) {
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: Int32(-amount), wheel2: 0, wheel3: 0) else { return }
        event.post(tap: .cghidEventTap)
    }

    static func scrollUp(amount: Int) {
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: Int32(amount), wheel2: 0, wheel3: 0) else { return }
        event.post(tap: .cghidEventTap)
    }
}
