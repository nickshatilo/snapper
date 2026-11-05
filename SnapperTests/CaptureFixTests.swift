import AppKit
import CoreGraphics
import XCTest
@testable import Snapper

final class CaptureFixTests: XCTestCase {
    private typealias RGBA = (r: UInt8, g: UInt8, b: UInt8, a: UInt8)

    // MARK: - Helpers

    /// An image whose top half is `top` and bottom half is `bottom`.
    private func splitImage(width: Int, height: Int, top: CGColor, bottom: CGColor, space: CGColorSpace? = nil) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space ?? CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        // CGContext is y-up: the upper half is y >= height / 2.
        context.setFillColor(top)
        context.fill(CGRect(x: 0, y: height / 2, width: width, height: height - height / 2))
        context.setFillColor(bottom)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height / 2))
        return context.makeImage()!
    }

    /// Reads a pixel with (0, 0) at the image's top-left (CGImage row order).
    private func pixel(_ image: CGImage, x: Int, y: Int) -> RGBA {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(
            data: &bytes,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let offset = (y * image.width + x) * 4
        return (bytes[offset], bytes[offset + 1], bytes[offset + 2], bytes[offset + 3])
    }

    private let red = CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
    private let blue = CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)
    private let green = CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)
    private let yellow = CGColor(srgbRed: 1, green: 1, blue: 0, alpha: 1)

    private func assertColor(_ actual: RGBA, _ expected: (UInt8, UInt8, UInt8), _ message: String, line: UInt = #line) {
        XCTAssertEqual(actual.r, expected.0, message, line: line)
        XCTAssertEqual(actual.g, expected.1, message, line: line)
        XCTAssertEqual(actual.b, expected.2, message, line: line)
        XCTAssertEqual(actual.a, 255, message, line: line)
    }

    // MARK: - Fullscreen / multi-display composition

    func testComposeDisplaysKeepsSingleDisplayUpright() {
        let image = splitImage(width: 4, height: 4, top: red, bottom: blue)
        let composed = ScreenCaptureService.composeDisplays(
            [(frame: CGRect(x: 0, y: 0, width: 4, height: 4), image: image)],
            canvasScale: 1
        )!
        assertColor(pixel(composed.image, x: 1, y: 0), (255, 0, 0), "top row must stay red")
        assertColor(pixel(composed.image, x: 1, y: 3), (0, 0, 255), "bottom row must stay blue")
    }

    func testComposeDisplaysPlacesDisplaysInCGTopLeftSpace() {
        // CG global points: a 4x4 primary at the origin, and a 2x2 secondary to
        // its right whose top edge is 2pt *above* the primary's (negative y).
        let primary = splitImage(width: 4, height: 4, top: red, bottom: blue)
        let secondary = splitImage(width: 2, height: 2, top: green, bottom: yellow)
        let composed = ScreenCaptureService.composeDisplays(
            [
                (frame: CGRect(x: 0, y: 0, width: 4, height: 4), image: primary),
                (frame: CGRect(x: 4, y: -2, width: 2, height: 2), image: secondary),
            ],
            canvasScale: 1
        )!

        XCTAssertEqual(composed.unionRect, CGRect(x: 0, y: -2, width: 6, height: 6))
        XCTAssertEqual(composed.image.width, 6)
        XCTAssertEqual(composed.image.height, 6)

        // Image row r corresponds to CG y = unionRect.minY + r.
        assertColor(pixel(composed.image, x: 4, y: 0), (0, 255, 0), "secondary top (y=-2)")
        assertColor(pixel(composed.image, x: 4, y: 1), (255, 255, 0), "secondary bottom (y=-1)")
        assertColor(pixel(composed.image, x: 0, y: 2), (255, 0, 0), "primary top (y=0)")
        assertColor(pixel(composed.image, x: 0, y: 5), (0, 0, 255), "primary bottom (y=3)")
        XCTAssertEqual(pixel(composed.image, x: 4, y: 3).a, 0, "gap below secondary stays empty")
    }

    func testComposeDisplaysScalesToRetinaCanvas() {
        let image = splitImage(width: 8, height: 8, top: red, bottom: blue)
        let composed = ScreenCaptureService.composeDisplays(
            [(frame: CGRect(x: 0, y: 0, width: 4, height: 4), image: image)],
            canvasScale: 2
        )!
        XCTAssertEqual(composed.image.width, 8)
        XCTAssertEqual(composed.image.height, 8)
        assertColor(pixel(composed.image, x: 0, y: 0), (255, 0, 0), "top-left stays red at 2x")
        assertColor(pixel(composed.image, x: 7, y: 7), (0, 0, 255), "bottom-right stays blue at 2x")
    }

    func testComposeDisplaysPreservesDisplayColorSpace() {
        let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
        let image = splitImage(width: 2, height: 2, top: red, bottom: blue, space: p3)
        let composed = ScreenCaptureService.composeDisplays(
            [(frame: CGRect(x: 0, y: 0, width: 2, height: 2), image: image)],
            canvasScale: 1
        )!
        XCTAssertEqual(composed.image.colorSpace?.name, CGColorSpace.displayP3)
    }

    func testThumbnailPreservesColorSpace() {
        let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
        let image = splitImage(width: 400, height: 200, top: red, bottom: blue, space: p3)
        let thumbnail = ImageUtils.generateThumbnail(image, maxWidth: 100)
        XCTAssertEqual(thumbnail?.colorSpace?.name, CGColorSpace.displayP3)
    }

    // MARK: - Window hit-test ordering

    func testSortedFrontToBackFollowsWindowServerOrder() {
        // SCShareableContent order (arbitrary) vs CGWindowList order (front to back).
        let shareableOrder: [CGWindowID] = [30, 10, 99, 20]
        let zOrder: [CGWindowID] = [20, 5, 10, 30]
        let sorted = WindowSelectorController.sortedFrontToBack(shareableOrder, id: { $0 }, zOrder: zOrder)
        XCTAssertEqual(sorted, [20, 10, 30, 99], "unknown windows go last")
    }

    func testWindowSelectionFilterAcceptsFloatingButNotDockOrOwnWindows() {
        let size = CGSize(width: 400, height: 300)
        let ownPID: pid_t = 100
        let otherPID: pid_t = 200
        let floating = Int(CGWindowLevelForKey(.floatingWindow))
        let dock = Int(CGWindowLevelForKey(.dockWindow))
        XCTAssertEqual(dock, 20)

        func selectable(_ layer: Int, _ size: CGSize = CGSize(width: 400, height: 300), pid: pid_t? = 200) -> Bool {
            WindowSelectorController.isSelectable(layer: layer, size: size, ownerPID: pid, ownPID: ownPID)
        }
        XCTAssertTrue(selectable(0), "normal windows")
        XCTAssertTrue(selectable(floating), "floating / always-on-top windows")
        XCTAssertTrue(selectable(dock - 1))
        XCTAssertFalse(selectable(dock), "Dock level and above are system chrome")
        XCTAssertFalse(selectable(Int(CGWindowLevelForKey(.mainMenuWindow))))
        XCTAssertFalse(selectable(-1), "desktop-level windows")
        XCTAssertFalse(selectable(0, pid: ownPID), "Snapper's own windows")
        XCTAssertFalse(selectable(0, CGSize(width: 40, height: 300)), "too small")
        XCTAssertTrue(selectable(0, size, pid: otherPID))
        XCTAssertTrue(selectable(0, pid: nil), "windows without an owning app are kept")
    }
}
