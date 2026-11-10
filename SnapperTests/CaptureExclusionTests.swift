import CoreGraphics
import XCTest
@testable import Snapper

final class CaptureExclusionTests: XCTestCase {
    private let ownPID: pid_t = 4242
    private let otherPID: pid_t = 777

    func testOwnFloatingWindowIsExcluded() {
        let floatingLayer = Int(CGWindowLevelForKey(.floatingWindow))

        XCTAssertTrue(ScreenCaptureService.isOwnOverlayWindow(
            ownerPID: ownPID,
            layer: floatingLayer,
            ownPID: ownPID
        ))
    }

    func testOwnSelectionOverlayLevelIsExcluded() {
        let overlayLayer = Int(CGWindowLevelForKey(.maximumWindow))

        XCTAssertTrue(ScreenCaptureService.isOwnOverlayWindow(
            ownerPID: ownPID,
            layer: overlayLayer,
            ownPID: ownPID
        ))
    }

    func testOwnNormalLevelWindowStaysCapturable() {
        XCTAssertFalse(ScreenCaptureService.isOwnOverlayWindow(
            ownerPID: ownPID,
            layer: 0,
            ownPID: ownPID
        ))
    }

    func testOtherApplicationsFloatingWindowStaysCapturable() {
        let floatingLayer = Int(CGWindowLevelForKey(.floatingWindow))

        XCTAssertFalse(ScreenCaptureService.isOwnOverlayWindow(
            ownerPID: otherPID,
            layer: floatingLayer,
            ownPID: ownPID
        ))
    }

    func testWindowWithoutOwnerStaysCapturable() {
        let floatingLayer = Int(CGWindowLevelForKey(.floatingWindow))

        XCTAssertFalse(ScreenCaptureService.isOwnOverlayWindow(
            ownerPID: nil,
            layer: floatingLayer,
            ownPID: ownPID
        ))
    }
}
