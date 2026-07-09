import AppKit
import XCTest
@testable import Snapper

@MainActor
final class PinnedScreenshotPanelTests: XCTestCase {
    func testLockedPanelKeepsUnlockMenuReachableWhileFreezingGeometry() throws {
        let panel = PinnedScreenshotPanel(
            image: try makeImage(),
            frame: NSRect(x: 0, y: 0, width: 100, height: 100)
        )

        panel.isLocked = true

        XCTAssertFalse(panel.ignoresMouseEvents, "locked pins must still receive the Unlock click")
        XCTAssertFalse(panel.isMovable)
        XCTAssertFalse(panel.isMovableByWindowBackground)
        XCTAssertFalse(panel.styleMask.contains(.resizable))

        panel.isLocked = false

        XCTAssertFalse(panel.ignoresMouseEvents)
        XCTAssertTrue(panel.isMovable)
        XCTAssertTrue(panel.isMovableByWindowBackground)
        XCTAssertTrue(panel.styleMask.contains(.resizable))
    }

    private func makeImage() throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: 2,
            height: 2,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage() else {
            throw TestError.imageCreationFailed
        }
        return image
    }

    private enum TestError: Error {
        case imageCreationFailed
    }
}
