import AppKit
import Carbon.HIToolbox
import ImageIO
import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import Snapper

final class ShellFixTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShellFixTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Collision-safe file naming

    func testReserveUniqueURLClaimsNamesInOrder() throws {
        let url = directory.appendingPathComponent("shot.png")

        let first = try XCTUnwrap(FileManager.default.reserveUniqueURL(for: url))
        let second = try XCTUnwrap(FileManager.default.reserveUniqueURL(for: url))

        XCTAssertEqual(first, url)
        XCTAssertEqual(second.lastPathComponent, "shot 2.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path), "the reservation must exist on disk")
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
    }

    func testConcurrentReservationsNeverShareAName() {
        let url = directory.appendingPathComponent("Snapper 2026-11-05 at 10.00.00.png")
        let count = 64
        var results = [URL?](repeating: nil, count: count)
        let lock = NSLock()

        DispatchQueue.concurrentPerform(iterations: count) { index in
            let reserved = FileManager.default.reserveUniqueURL(for: url)
            lock.lock()
            results[index] = reserved
            lock.unlock()
        }

        let reserved = results.compactMap { $0 }
        XCTAssertEqual(reserved.count, count)
        XCTAssertEqual(Set(reserved).count, count, "two concurrent saves were handed the same file name")
    }

    func testReserveUniqueURLFailsForUnwritableDirectory() {
        let url = directory.appendingPathComponent("missing/shot.png")
        XCTAssertNil(FileManager.default.reserveUniqueURL(for: url))
    }

    // MARK: - Filename pattern

    func testEmptyOrWhitespacePatternFallsBackToDefault() {
        for pattern in ["", "   ", "\n\t"] {
            let name = FileNameGenerator.generate(pattern: pattern, mode: .area)
            XCTAssertTrue(name.hasPrefix("Snapper "), "pattern \(pattern.debugDescription) produced \(name.debugDescription)")
            XCTAssertFalse(name.isEmpty)
        }
    }

    func testPatternThatSanitizesToNothingFallsBackToDefault() {
        let name = FileNameGenerator.generate(pattern: "...", mode: .area)
        XCTAssertTrue(name.hasPrefix("Snapper "), "got \(name.debugDescription)")
    }

    func testGeneratedNameHasNoPathSeparatorsColonsOrLeadingDot() {
        let name = FileNameGenerator.generate(
            pattern: ".hidden/{app}:{type}",
            mode: .window,
            appName: "AC/DC: Live"
        )
        XCTAssertFalse(name.contains("/"))
        XCTAssertFalse(name.contains(":"))
        XCTAssertFalse(name.hasPrefix("."))
        XCTAssertFalse(name.isEmpty)
    }

    func testEmptyPatternStaysInsideSaveDirectory() {
        let name = FileNameGenerator.generate(pattern: "", mode: .fullscreen)
        let url = directory.appendingPathComponent(name).appendingPathExtension("png")
        XCTAssertEqual(url.deletingLastPathComponent().standardizedFileURL, directory.standardizedFileURL)
    }

    // MARK: - Pinned screenshots

    func testDefaultPinSizeKeepsAspectRatio() {
        // 1600×200 pt at 2x: half size is 800×100, which must scale to 400×50.
        let size = PinnedScreenshotPanel.defaultSize(forPixelWidth: 3200, pixelHeight: 400, scale: 2)
        XCTAssertEqual(size.width, 400, accuracy: 0.001)
        XCTAssertEqual(size.height, 50, accuracy: 0.001)

        let tall = PinnedScreenshotPanel.defaultSize(forPixelWidth: 400, pixelHeight: 2400, scale: 1)
        XCTAssertEqual(tall.height, 300, accuracy: 0.001)
        XCTAssertEqual(tall.width / tall.height, 400.0 / 2400.0, accuracy: 0.0001)
    }

    func testSmallPinIsNotUpscaled() {
        let size = PinnedScreenshotPanel.defaultSize(forPixelWidth: 400, pixelHeight: 200, scale: 1)
        XCTAssertEqual(size, NSSize(width: 200, height: 100))
    }

    @MainActor
    func testPinnedPanelReportsMoveAndOpacityChanges() throws {
        let panel = PinnedScreenshotPanel(
            image: try makeImage(width: 4, height: 4),
            frame: NSRect(x: 100, y: 100, width: 120, height: 120)
        )
        var changes = 0
        panel.onStateChange = { changes += 1 }

        panel.setFrameOrigin(NSPoint(x: 140, y: 160))
        XCTAssertGreaterThan(changes, 0, "moving a pin must trigger persistence")

        let afterMove = changes
        panel.currentOpacity = 0.5
        XCTAssertGreaterThan(changes, afterMove, "changing opacity must trigger persistence")
    }

    // MARK: - History store recovery

    func testCorruptHistoryStoreIsMovedAsideInsteadOfCrashing() throws {
        let storeURL = directory.appendingPathComponent("History.store")
        try Data(repeating: 0x42, count: 4096).write(to: storeURL)

        let manager = HistoryManager(storeURL: storeURL)

        let context = ModelContext(manager.modelContainer)
        context.insert(CaptureRecord(captureType: "area", width: 1, height: 1, filePath: ""))
        XCTAssertNoThrow(try context.save())
        XCTAssertEqual(try context.fetch(FetchDescriptor<CaptureRecord>()).count, 1)

        let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertTrue(
            contents.contains { $0.hasPrefix("History.store.broken-") },
            "the broken store should be kept for inspection, got \(contents)"
        )
    }

    func testUnreadableHistoryStoreIsLeftUntouched() throws {
        let storeURL = directory.appendingPathComponent("History.store")
        let original = Data(repeating: 0x42, count: 4096)
        try original.write(to: storeURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: storeURL.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: storeURL.path) }

        XCTAssertEqual(HistoryManager.diagnoseStore(at: storeURL), .transient)

        let manager = HistoryManager(storeURL: storeURL)
        let context = ModelContext(manager.modelContainer)
        context.insert(CaptureRecord(captureType: "area", width: 1, height: 1, filePath: ""))
        XCTAssertNoThrow(try context.save(), "should fall back to an in-memory store")

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: storeURL.path)
        XCTAssertEqual(try Data(contentsOf: storeURL), original, "a transient failure must not touch the store")
        let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertFalse(contents.contains { $0.contains("broken") }, "got \(contents)")
    }

    func testOCRCopyIsDownscaledBelowRecognitionCap() throws {
        let large = try makeImage(width: 6000, height: 1500)
        let scaled = HistoryManager.downscaledForOCR(large)
        XCTAssertEqual(scaled.width, 2400)
        XCTAssertEqual(scaled.height, 600)

        let small = try makeImage(width: 800, height: 600)
        XCTAssertTrue(HistoryManager.downscaledForOCR(small) === small)
    }

    // MARK: - Quick access image cache

    func testQuickAccessImageCacheNoticesReplacedAndDeletedFiles() throws {
        let url = directory.appendingPathComponent("screenshot.png")
        try writePNG(makeImage(width: 2, height: 2), to: url)
        let capture = makeCapture(savedURL: url)

        XCTAssertEqual(capture.resolvedImage()?.width, 2)

        // A later capture reuses the name with different content.
        try FileManager.default.removeItem(at: url)
        try writePNG(makeImage(width: 6, height: 6), to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(60)],
            ofItemAtPath: url.path
        )
        XCTAssertEqual(capture.resolvedImage()?.width, 6, "stale cached image returned for a replaced file")

        try FileManager.default.removeItem(at: url)
        XCTAssertNil(capture.resolvedImage(), "a deleted file must not resolve from the cache")
    }

    // MARK: - Hotkey recorder

    @MainActor
    func testRecorderStopsRecordingWhenWindowCloses() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 40),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let recorder = HotkeyRecorderNSView(frame: NSRect(x: 0, y: 0, width: 160, height: 24))
        window.contentView?.addSubview(recorder)
        recorder.updateDisplay(binding: HotkeyBinding(keyCode: kVK_ANSI_4, modifiers: [.maskCommand, .maskShift]))

        let click = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
        recorder.mouseDown(with: click)
        XCTAssertTrue(HotkeyRecorderNSView.activeRecorder === recorder)

        window.close()

        XCTAssertNil(HotkeyRecorderNSView.activeRecorder, "closing Settings must end recording")
        // The prompt is replaced by the existing binding again.
        let field = try XCTUnwrap(recorder.subviews.compactMap { $0 as? NSTextField }.first)
        XCTAssertEqual(field.stringValue, "⇧⌘4")
    }

    @MainActor
    func testInterceptedBindingIsDeliveredOnlyWhileRecording() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 40),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let recorder = HotkeyRecorderNSView(frame: NSRect(x: 0, y: 0, width: 160, height: 24))
        window.contentView?.addSubview(recorder)
        var captured: [HotkeyBinding] = []
        recorder.onBindingCaptured = { captured.append($0) }
        let binding = HotkeyBinding(keyCode: kVK_ANSI_3, modifiers: [.maskCommand, .maskShift])

        recorder.receiveInterceptedBinding(binding)
        XCTAssertTrue(captured.isEmpty, "not recording yet")

        let click = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
        recorder.mouseDown(with: click)
        recorder.receiveInterceptedBinding(binding)

        XCTAssertEqual(captured, [binding])
        XCTAssertNil(HotkeyRecorderNSView.activeRecorder, "capturing a binding ends recording")
    }

    // MARK: - Helpers

    private func makeCapture(savedURL: URL) -> QuickAccessCapture {
        QuickAccessCapture(
            id: UUID(),
            recordID: UUID(),
            inMemoryImage: nil,
            thumbnail: try! makeImage(width: 1, height: 1),
            mode: .area,
            timestamp: Date(),
            savedURL: savedURL,
            width: 2,
            height: 2,
            fileSize: 0,
            scale: 1
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
        ) else { throw NSError(domain: "ShellFixTests", code: 1) }
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { throw NSError(domain: "ShellFixTests", code: 2) }
        return image
    }

    private func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else { throw NSError(domain: "ShellFixTests", code: 3) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "ShellFixTests", code: 4) }
    }
}
