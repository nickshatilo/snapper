import XCTest
@testable import Snapper

final class SnapperTests: XCTestCase {
    func testCaptureModeCases() {
        XCTAssertEqual(CaptureMode.allCases.count, 6)
        XCTAssertEqual(CaptureMode.fullscreen.displayName, "Fullscreen")
    }

    func testImageFormatExtensions() {
        XCTAssertEqual(ImageFormat.png.fileExtension, "png")
        XCTAssertEqual(ImageFormat.jpeg.fileExtension, "jpeg")
        XCTAssertEqual(ImageFormat.tiff.fileExtension, "tiff")
    }

    func testToolTypeShortcuts() {
        XCTAssertEqual(ToolType.arrow.shortcutKey, "A")
        XCTAssertEqual(ToolType.rectangle.shortcutKey, "R")
        XCTAssertEqual(ToolType.crop.shortcutKey, "C")
        XCTAssertEqual(ToolType.allCases.count, 14)
    }

    func testCounterStyleDisplay() {
        XCTAssertEqual(CounterStyle.numbers.display(for: 1), "1")
        XCTAssertEqual(CounterStyle.letters.display(for: 1), "A")
        XCTAssertEqual(CounterStyle.roman.display(for: 4), "IV")
    }

    func testFileNameGenerator() {
        let name = FileNameGenerator.generate(pattern: "test-{type}", mode: .fullscreen, appName: "Safari")
        XCTAssertTrue(name.contains("Fullscreen"))
    }

    func testBackgroundTemplateBuiltIn() {
        XCTAssertFalse(BackgroundTemplate.builtIn.isEmpty)
        XCTAssertEqual(BackgroundTemplate.builtIn.count, 6)
    }

    func testOverlayCornerCases() {
        XCTAssertEqual(OverlayCorner.allCases.count, 4)
        XCTAssertEqual(OverlayCorner.bottomRight.displayName, "Bottom Right")
    }
}
