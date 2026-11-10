import XCTest
import CoreGraphics
import ImageIO
import AppKit
@testable import Snapper

final class EditorExportTests: XCTestCase {
    // MARK: - Helpers

    private func solidImage(width: Int = 40, height: Int = 30) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private func makeRect(_ x: CGFloat = 0) -> RectangleAnnotation {
        RectangleAnnotation(rect: CGRect(x: x, y: 0, width: 10, height: 10), strokeColor: .red, fillColor: nil, strokeWidth: 1)
    }

    private func rect(_ source: RectangleAnnotation, width: CGFloat) -> RectangleAnnotation {
        RectangleAnnotation(id: source.id, rect: source.rect, strokeColor: source.strokeColor, fillColor: nil, strokeWidth: width)
    }

    // MARK: - Unsaved-change tracking

    func testFreshStateHasNoUnsavedChanges() {
        let state = CanvasState(image: solidImage())
        XCTAssertFalse(state.hasUnsavedChanges)
        XCTAssertNil(state.lastSavedURL)
        XCTAssertEqual(state.savedRevision, 0)
    }

    func testEditsAreUnsavedUntilMarkedSaved() {
        let state = CanvasState(image: solidImage())

        state.addAnnotation(makeRect())
        XCTAssertTrue(state.hasUnsavedChanges)

        state.markSaved()
        XCTAssertFalse(state.hasUnsavedChanges)

        // The saved copy still has the rectangle, so undoing it is a change
        // even though the undo stack is empty again.
        state.undoManager.undo(state: state)
        XCTAssertFalse(state.undoManager.canUndo)
        XCTAssertTrue(state.hasUnsavedChanges)

        state.markSaved()
        XCTAssertFalse(state.hasUnsavedChanges)
    }

    func testNeverSavedStateIsCleanOnceEverythingIsUndone() {
        let state = CanvasState(image: solidImage())
        state.addAnnotation(makeRect(0))
        state.addAnnotation(makeRect(20))
        XCTAssertTrue(state.hasUnsavedChanges)

        state.undoManager.undo(state: state)
        XCTAssertTrue(state.hasUnsavedChanges)
        state.undoManager.undo(state: state)
        XCTAssertFalse(state.hasUnsavedChanges)

        state.undoManager.redo(state: state)
        XCTAssertTrue(state.hasUnsavedChanges)
    }

    func testAbandonedCreationLeavesNeverSavedStateClean() {
        let state = CanvasState(image: solidImage())
        let text = TextAnnotation(position: .zero, text: TextAnnotation.placeholderText, fontName: "Helvetica", fontSize: 16, color: .red)
        state.addAnnotation(text)
        XCTAssertTrue(state.hasUnsavedChanges)

        XCTAssertTrue(state.undoManager.discardLastAdd(of: text.id))
        XCTAssertFalse(state.hasUnsavedChanges)
    }

    func testCoalescedEditAfterSaveCountsAsUnsaved() {
        let state = CanvasState(image: solidImage())
        let original = makeRect()
        state.addAnnotation(original)
        state.replaceAnnotations([rect(original, width: 4)], coalescingKey: "width")
        state.markSaved()
        XCTAssertFalse(state.hasUnsavedChanges)

        // Folds into the existing undo entry rather than adding one.
        state.replaceAnnotations([rect(original, width: 8)], coalescingKey: "width")
        XCTAssertEqual(state.undoManager.undoCount, 2)
        XCTAssertTrue(state.hasUnsavedChanges)
    }

    func testRevisionIncreasesOnEveryHistoryChange() {
        let state = CanvasState(image: solidImage())
        let manager = state.undoManager
        XCTAssertEqual(manager.revision, 0)

        var last = manager.revision
        func assertBumped(_ step: String, line: UInt = #line) {
            XCTAssertGreaterThan(manager.revision, last, step, line: line)
            last = manager.revision
        }

        let original = makeRect()
        state.addAnnotation(original)
        assertBumped("add")

        XCTAssertTrue(manager.replaceLastAdd(with: rect(original, width: 2)))
        assertBumped("replaceLastAdd")

        state.replaceAnnotations([rect(original, width: 4)], coalescingKey: "width")
        assertBumped("modify")
        state.replaceAnnotations([rect(original, width: 8)], coalescingKey: "width")
        assertBumped("coalesced modify")

        manager.undo(state: state)
        assertBumped("undo")
        manager.redo(state: state)
        assertBumped("redo")

        state.removeAnnotation(id: original.id)
        assertBumped("remove")

        let extra = makeRect(20)
        state.addAnnotation(extra)
        assertBumped("second add")
        XCTAssertTrue(manager.discardLastAdd(of: extra.id))
        assertBumped("discardLastAdd")

        // Nothing to redo: the history, and so the revision, is untouched.
        manager.redo(state: state)
        XCTAssertEqual(manager.revision, last)
    }

    // MARK: - Source scale

    func testCanvasStateClampsSourceScale() {
        let image = solidImage()
        XCTAssertEqual(CanvasState(image: image).sourceScale, 1)
        XCTAssertEqual(CanvasState(image: image, scale: 2).sourceScale, 2)
        XCTAssertEqual(CanvasState(image: image, scale: 1.5).sourceScale, 1.5)
        XCTAssertEqual(CanvasState(image: image, scale: 0).sourceScale, 1)
        XCTAssertEqual(CanvasState(image: image, scale: 0.5).sourceScale, 1)
        XCTAssertEqual(CanvasState(image: image, scale: -2).sourceScale, 1)
        XCTAssertEqual(CanvasState(image: image, scale: .nan).sourceScale, 1)
        XCTAssertEqual(CanvasState(image: image, scale: .infinity).sourceScale, 1)
    }

    // MARK: - Saving

    func testFormatFollowsPathExtension() {
        XCTAssertEqual(EditorExporter.format(forPathExtension: "png"), .png)
        XCTAssertEqual(EditorExporter.format(forPathExtension: "JPG"), .jpeg)
        XCTAssertEqual(EditorExporter.format(forPathExtension: "jpeg"), .jpeg)
        XCTAssertEqual(EditorExporter.format(forPathExtension: "tiff"), .tiff)
        XCTAssertEqual(EditorExporter.format(forPathExtension: "tif"), .tiff)
        XCTAssertEqual(EditorExporter.format(forPathExtension: ""), .png)
        XCTAssertEqual(EditorExporter.format(forPathExtension: "gif"), .png)
    }

    func testAnnotatedFilenameContainsNoPathSeparators() {
        let name = FileNameGenerator.generate(pattern: EditorExporter.annotatedFilenamePattern, mode: .area)
        XCTAssertFalse(name.contains("/"))
        XCTAssertFalse(name.contains(":"))
        XCTAssertTrue(name.hasPrefix("Snapper Annotated"))
    }

    @MainActor
    func testSaveUsesOptionsThenOverwritesItsOwnFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        var options = CaptureOptions()
        options.saveDirectory = directory
        options.format = .tiff

        let state = CanvasState(image: solidImage(), scale: 2)
        state.addAnnotation(makeRect())

        XCTAssertTrue(EditorExporter.save(state, options: options))
        let savedURL = try XCTUnwrap(state.lastSavedURL)
        XCTAssertEqual(savedURL.deletingLastPathComponent().standardizedFileURL.path, directory.standardizedFileURL.path)
        XCTAssertEqual(savedURL.pathExtension, "tiff")
        XCTAssertTrue(savedURL.lastPathComponent.hasPrefix("Snapper Annotated"))
        XCTAssertFalse(state.hasUnsavedChanges)

        let source = try XCTUnwrap(CGImageSourceCreateWithURL(savedURL as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetType(source).map { $0 as String }, "public.tiff")
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let dpi = try XCTUnwrap(properties[kCGImagePropertyDPIWidth] as? Double)
        XCTAssertEqual(dpi, 144, accuracy: 1)

        // A later save goes back to the same file, whatever the settings say now.
        state.addAnnotation(makeRect(20))
        XCTAssertTrue(state.hasUnsavedChanges)
        options.format = .png
        XCTAssertTrue(EditorExporter.save(state, options: options))
        XCTAssertEqual(state.lastSavedURL, savedURL)
        XCTAssertFalse(state.hasUnsavedChanges)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 1)
    }

    // MARK: - Counter letters

    func testCounterLettersContinuePastZ() {
        XCTAssertEqual(CounterStyle.letters.display(for: 1), "A")
        XCTAssertEqual(CounterStyle.letters.display(for: 2), "B")
        XCTAssertEqual(CounterStyle.letters.display(for: 26), "Z")
        XCTAssertEqual(CounterStyle.letters.display(for: 27), "AA")
        XCTAssertEqual(CounterStyle.letters.display(for: 28), "AB")
        XCTAssertEqual(CounterStyle.letters.display(for: 52), "AZ")
        XCTAssertEqual(CounterStyle.letters.display(for: 53), "BA")
        XCTAssertEqual(CounterStyle.letters.display(for: 702), "ZZ")
        XCTAssertEqual(CounterStyle.letters.display(for: 703), "AAA")
    }

    func testCounterLettersBelowOneAreEmpty() {
        XCTAssertEqual(CounterStyle.letters.display(for: 0), "")
        XCTAssertEqual(CounterStyle.letters.display(for: -3), "")
    }
}
