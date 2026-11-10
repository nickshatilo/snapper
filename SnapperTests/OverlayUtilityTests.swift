import AppKit
import XCTest
@testable import Snapper

final class OverlayUtilityTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OverlayUtilityTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Saved image scale

    func testSaveRecordsScaleSoRetinaFileKeepsItsPointSize() throws {
        let image = try makeImage(width: 8, height: 6)

        for format in ImageFormat.allCases {
            let url = directory
                .appendingPathComponent("retina")
                .appendingPathExtension(format.fileExtension)
            XCTAssertTrue(ImageUtils.save(image, to: url, format: format, scale: 2), format.displayName)

            let loaded = try XCTUnwrap(NSImage(contentsOf: url), format.displayName)
            // PNG stores pixels per metre, so 144 dpi does not round-trip exactly.
            XCTAssertEqual(loaded.size.width, 4, accuracy: 0.05, format.displayName)
            XCTAssertEqual(loaded.size.height, 3, accuracy: 0.05, format.displayName)

            // The metadata must not cost any pixels when the file is read back.
            let pixels = try XCTUnwrap(
                loaded.cgImage(forProposedRect: nil, context: nil, hints: nil),
                format.displayName
            )
            XCTAssertEqual(pixels.width, 8, format.displayName)
            XCTAssertEqual(pixels.height, 6, format.displayName)
        }
    }

    func testSaveWithoutScaleKeepsPointSizeEqualToPixelSize() throws {
        let image = try makeImage(width: 8, height: 6)
        let url = directory.appendingPathComponent("plain.png")
        XCTAssertTrue(ImageUtils.save(image, to: url, format: .png))

        let loaded = try XCTUnwrap(NSImage(contentsOf: url))
        XCTAssertEqual(loaded.size.width, 8, accuracy: 0.05)
        XCTAssertEqual(loaded.size.height, 6, accuracy: 0.05)
    }

    // MARK: - Capture sounds

    func testCaptureSoundRawValuesStayStable() {
        // Raw values are persisted in UserDefaults; renaming one silently
        // resets the user's chosen sound.
        XCTAssertEqual(
            CaptureSound.allCases.map(\.rawValue),
            ["cameraShot", "glass", "tink", "pop", "funk", "hero", "submarine"]
        )
    }

    func testOnlyCameraShotIsLoadedFromAFile() {
        for sound in CaptureSound.allCases where sound != .cameraShot {
            XCTAssertNotNil(sound.nsSoundName, sound.rawValue)
            XCTAssertTrue(sound.fileCandidates.isEmpty, sound.rawValue)
        }

        let candidates = CaptureSound.cameraShot.fileCandidates
        XCTAssertFalse(candidates.isEmpty)
        for path in candidates {
            XCTAssertTrue(path.hasPrefix("/System/Library/"), path)
            XCTAssertEqual((path as NSString).pathExtension, "aif", path)
        }
    }

    // MARK: - Quick access

    func testMarkSavedGivesCaptureItsFileWithoutChangingIdentity() throws {
        let suiteName = "OverlayUtilityTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let manager = QuickAccessManager(appState: AppState(defaults: defaults))

        let image = try makeImage(width: 8, height: 6)
        let other = makeUnsavedCapture(image: image)
        let unsaved = makeUnsavedCapture(image: image)
        manager.captures = [other, unsaved]

        let url = directory.appendingPathComponent("saved.png")
        manager.markSaved(id: unsaved.id, url: url, fileSize: 1234)

        XCTAssertEqual(manager.captures.map(\.id), [other.id, unsaved.id])
        let saved = manager.captures[1]
        XCTAssertEqual(saved.recordID, unsaved.recordID)
        XCTAssertEqual(saved.savedURL, url)
        XCTAssertEqual(saved.fileSize, 1234)
        XCTAssertEqual(saved.scale, 2)
        XCTAssertTrue(saved.resolvedImage() === image, "the capture must stay usable without re-reading the file")
        XCTAssertNil(manager.captures[0].savedURL, "other captures must be left alone")

        // A capture dismissed while the save panel was open is simply gone.
        manager.markSaved(id: UUID(), url: url, fileSize: 1)
        XCTAssertEqual(manager.captures.map(\.fileSize), [0, 1234])
    }

    // MARK: - Helpers

    private func makeUnsavedCapture(image: CGImage) -> QuickAccessCapture {
        QuickAccessCapture(
            id: UUID(),
            recordID: UUID(),
            inMemoryImage: image,
            thumbnail: image,
            mode: .area,
            timestamp: Date(),
            savedURL: nil,
            width: image.width,
            height: image.height,
            fileSize: 0,
            scale: 2
        )
    }

    private func makeImage(width: Int, height: Int) throws -> CGImage {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw NSError(domain: "OverlayUtilityTests", code: 1) }
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { throw NSError(domain: "OverlayUtilityTests", code: 2) }
        return image
    }
}
