import AppKit
import Carbon.HIToolbox
import CoreGraphics
import XCTest
@testable import Snapper

final class BugFixTests: XCTestCase {
    // MARK: - Coordinate space

    func testAppKitToCGFlipsAroundPrimaryScreen() {
        // On a 1000pt-tall primary screen, an AppKit rect near the top
        // (minY 800, maxY 850) is 150pt from the top in CG space.
        let rect = CGRect(x: 10, y: 800, width: 100, height: 50)
        let converted = CoordinateSpace.appKitToCG(rect, primaryScreenMaxY: 1000)
        XCTAssertEqual(converted, CGRect(x: 10, y: 150, width: 100, height: 50))
    }

    func testAppKitToCGIsItsOwnInverse() {
        let rect = CGRect(x: -320, y: 250, width: 640, height: 400)
        let roundTripped = CoordinateSpace.appKitToCG(
            CoordinateSpace.appKitToCG(rect, primaryScreenMaxY: 900),
            primaryScreenMaxY: 900
        )
        XCTAssertEqual(roundTripped, rect)
    }

    func testAppKitToCGPointConversion() {
        let point = CGPoint(x: 42, y: 100)
        XCTAssertEqual(
            CoordinateSpace.appKitToCG(point, primaryScreenMaxY: 900),
            CGPoint(x: 42, y: 800)
        )
    }

    // MARK: - Frozen area capture

    func testFrozenSnapshotCropsTheFrameCapturedAtSelectionStart() throws {
        let displayImage = makeTwoBandImage(
            width: 8,
            height: 8,
            top: (255, 0, 0),
            bottom: (0, 0, 255)
        )
        let snapshot = FrozenScreenSnapshot(displays: [
            .init(frame: CGRect(x: 0, y: 0, width: 4, height: 4), image: displayImage),
        ])

        let topHalf = try XCTUnwrap(snapshot.image(
            for: CGRect(x: 0, y: 2, width: 4, height: 2),
            retinaScale: true
        ))
        XCTAssertEqual(topHalf.width, 8)
        XCTAssertEqual(topHalf.height, 4)
        XCTAssertEqual(pixel(in: topHalf, x: 4, y: 2).red, 255)
        XCTAssertEqual(pixel(in: topHalf, x: 4, y: 2).blue, 0)

        let bottomHalf = try XCTUnwrap(snapshot.image(
            for: CGRect(x: 0, y: 0, width: 4, height: 2),
            retinaScale: true
        ))
        XCTAssertEqual(pixel(in: bottomHalf, x: 4, y: 2).red, 0)
        XCTAssertEqual(pixel(in: bottomHalf, x: 4, y: 2).blue, 255)
    }

    func testFrozenSnapshotComposesSelectionsAcrossDisplays() throws {
        let snapshot = FrozenScreenSnapshot(displays: [
            .init(
                frame: CGRect(x: 0, y: 0, width: 4, height: 4),
                image: makeSolidImage(width: 8, height: 8, red: 255, green: 0, blue: 0)
            ),
            .init(
                frame: CGRect(x: 4, y: 0, width: 4, height: 4),
                image: makeSolidImage(width: 8, height: 8, red: 0, green: 255, blue: 0)
            ),
        ])

        let image = try XCTUnwrap(snapshot.image(
            for: CGRect(x: 2, y: 1, width: 4, height: 2),
            retinaScale: false
        ))
        XCTAssertEqual(image.width, 4)
        XCTAssertEqual(image.height, 2)
        XCTAssertEqual(pixel(in: image, x: 0, y: 1).red, 255)
        XCTAssertEqual(pixel(in: image, x: 3, y: 1).green, 255)
    }

    func testFreezeScreenDefaultsOnButRespectsAnExplicitPreference() {
        let suiteName = "BugFixTests.freezeScreen.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertTrue(AppState(defaults: defaults).freezeScreen)
        defaults.set(false, forKey: Constants.Keys.freezeScreen)
        XCTAssertFalse(AppState(defaults: defaults).freezeScreen)
    }

    // MARK: - Filename collisions

    func testUniqueURLAppendsCounterOnCollision() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("shot.png")
        XCTAssertEqual(FileManager.default.uniqueURL(for: url), url)

        FileManager.default.createFile(atPath: url.path, contents: Data())
        let second = FileManager.default.uniqueURL(for: url)
        XCTAssertEqual(second.lastPathComponent, "shot 2.png")

        FileManager.default.createFile(atPath: second.path, contents: Data())
        XCTAssertEqual(FileManager.default.uniqueURL(for: url).lastPathComponent, "shot 3.png")
    }

    func testAnnotatedSavePatternContainsNoPathSeparators() {
        let name = FileNameGenerator.generate(
            pattern: "Snapper Annotated {date} at {time}",
            mode: .area
        )
        XCTAssertFalse(name.contains("/"))
        XCTAssertFalse(name.contains(":"))
        XCTAssertTrue(name.hasPrefix("Snapper Annotated"))
    }

    // MARK: - Hotkey matching

    func testHotkeyBindingRequiresExactModifiers() {
        let binding = HotkeyBinding(keyCode: kVK_ANSI_4, modifiers: [.maskCommand, .maskShift])

        XCTAssertTrue(binding.matches(keyCode: kVK_ANSI_4, flags: [.maskCommand, .maskShift]))
        // ⌘⌃⇧4 is macOS's clipboard-screenshot shortcut and must not match.
        XCTAssertFalse(binding.matches(keyCode: kVK_ANSI_4, flags: [.maskCommand, .maskShift, .maskControl]))
        XCTAssertFalse(binding.matches(keyCode: kVK_ANSI_4, flags: [.maskCommand, .maskShift, .maskAlternate]))
        XCTAssertFalse(binding.matches(keyCode: kVK_ANSI_4, flags: [.maskCommand]))
        XCTAssertFalse(binding.matches(keyCode: kVK_ANSI_3, flags: [.maskCommand, .maskShift]))
    }

    func testHotkeyBindingIgnoresDeviceDependentFlags() {
        let binding = HotkeyBinding(keyCode: kVK_ANSI_3, modifiers: [.maskCommand, .maskShift])
        let flags: CGEventFlags = [.maskCommand, .maskShift, .maskNonCoalesced]
        XCTAssertTrue(binding.matches(keyCode: kVK_ANSI_3, flags: flags))
    }

    func testHotkeyBindingsRoundTripThroughJSON() throws {
        let original = HotkeyBinding.defaultBindings
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([HotkeyAction: HotkeyBinding].self, from: data)
        XCTAssertEqual(decoded, original)
    }

    // MARK: - Scroll stitcher

    func testScrollStitcherStopsAtMaxHeight() {
        let initial = makeSolidImage(width: 8, height: 8, red: 255, green: 255, blue: 255)
        let frame = makeSolidImage(width: 8, height: 8, red: 0, green: 0, blue: 0)
        let stitcher = ScrollStitcher(initialImage: initial, maxHeight: 14)

        XCTAssertTrue(stitcher.append(frame: frame, verticalShift: 6))
        XCTAssertTrue(stitcher.reachedMaxHeight)
        XCTAssertFalse(stitcher.append(frame: frame, verticalShift: 6))
        XCTAssertEqual(stitcher.image.height, 14)
    }

    func testScrollStitcherKeepsSegmentsUpright() {
        // Initial: top half white, bottom half black. Second frame carries a
        // green strip in its bottom 4 rows. The composite must read
        // white / black / green from top to bottom with no mirroring.
        let initial = makeTwoBandImage(
            width: 8, height: 8,
            top: (255, 255, 255), bottom: (0, 0, 0)
        )
        let frame = makeTwoBandImage(
            width: 8, height: 8,
            top: (128, 128, 128), bottom: (0, 255, 0)
        )
        let stitcher = ScrollStitcher(initialImage: initial)

        XCTAssertTrue(stitcher.append(frame: frame, verticalShift: 4))
        let composite = stitcher.image
        XCTAssertEqual(composite.height, 12)

        XCTAssertEqual(pixel(in: composite, x: 4, y: 1).red, 255, "top of initial frame should stay on top")
        XCTAssertEqual(pixel(in: composite, x: 4, y: 6).red, 0, "bottom of initial frame should stay above the strip")
        let stripPixel = pixel(in: composite, x: 4, y: 10)
        XCTAssertEqual(stripPixel.green, 255, "appended strip should be the frame's bottom rows")
        XCTAssertEqual(stripPixel.red, 0)
    }

    // MARK: - Scroll frame store

    func testScrollFrameStoreNeverRegressesToStaleFrames() async {
        let store = ScrollFrameStore()
        let image = makeSolidImage(width: 2, height: 2, red: 0, green: 0, blue: 0)

        await store.store(ScrollCapturedFrame(sequence: 2, image: image))
        await store.store(ScrollCapturedFrame(sequence: 1, image: image))

        let frame = await store.waitForNextFrame(after: 0, timeout: 0.2)
        XCTAssertEqual(frame?.sequence, 2)
    }

    func testScrollFrameStoreWaiterTimesOut() async {
        let store = ScrollFrameStore()
        let frame = await store.waitForNextFrame(after: 0, timeout: 0.1)
        XCTAssertNil(frame)
    }

    // MARK: - Thumbnails

    func testGenerateThumbnailRejectsZeroSizedImages() {
        let image = makeSolidImage(width: 1, height: 1, red: 0, green: 0, blue: 0)
        XCTAssertNil(ImageUtils.resize(image, to: .zero))
        XCTAssertNotNil(ImageUtils.generateThumbnail(image))
    }

    // MARK: - Helpers

    private func makeSolidImage(width: Int, height: Int, red: UInt8, green: UInt8, blue: UInt8) -> CGImage {
        makeTwoBandImage(width: width, height: height, top: (red, green, blue), bottom: (red, green, blue))
    }

    private func makeTwoBandImage(
        width: Int,
        height: Int,
        top: (UInt8, UInt8, UInt8),
        bottom: (UInt8, UInt8, UInt8)
    ) -> CGImage {
        let bytesPerRow = width * 4
        var data = [UInt8](repeating: 0, count: height * bytesPerRow)
        for y in 0..<height {
            let color = y < height / 2 ? top : bottom
            for x in 0..<width {
                let index = y * bytesPerRow + x * 4
                data[index] = color.0
                data[index + 1] = color.1
                data[index + 2] = color.2
                data[index + 3] = 255
            }
        }

        let provider = CGDataProvider(data: Data(data) as CFData)!
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }

    private func pixel(in image: CGImage, x: Int, y: Int) -> (red: UInt8, green: UInt8, blue: UInt8) {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(
            data: &data,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let index = (y * image.width + x) * 4
        return (data[index], data[index + 1], data[index + 2])
    }
}
