import XCTest
import CoreGraphics
import AppKit
@testable import Snapper

final class EditorFixTests: XCTestCase {
    // MARK: - Helpers

    private struct Bitmap {
        let context: CGContext
        let width: Int
        let height: Int

        init(width: Int, height: Int) {
            self.width = width
            self.height = height
            context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
        }

        /// RGBA at a point in y-up user space.
        func pixel(x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
            let data = context.data!.assumingMemoryBound(to: UInt8.self)
            let row = height - 1 - y
            let offset = (row * width + x) * 4
            return (data[offset], data[offset + 1], data[offset + 2], data[offset + 3])
        }

        func fill(_ rect: CGRect, r: CGFloat, g: CGFloat, b: CGFloat) {
            context.setFillColor(red: r, green: g, blue: b, alpha: 1)
            context.fill(rect)
        }

        func image() -> CGImage { context.makeImage()! }
    }

    /// 100x100 image: bottom half (y < 50, y-up) red, top half blue.
    private func redBottomBlueTopImage() -> CGImage {
        let bitmap = Bitmap(width: 100, height: 100)
        bitmap.fill(CGRect(x: 0, y: 0, width: 100, height: 50), r: 1, g: 0, b: 0)
        bitmap.fill(CGRect(x: 0, y: 50, width: 100, height: 50), r: 0, g: 0, b: 1)
        return bitmap.image()
    }

    private func solidImage(width: Int, height: Int) -> CGImage {
        let bitmap = Bitmap(width: width, height: height)
        bitmap.fill(CGRect(x: 0, y: 0, width: width, height: height), r: 1, g: 1, b: 1)
        return bitmap.image()
    }

    private func minAlpha(of annotation: any Annotation, in rect: CGRect, canvasWidth: Int, canvasHeight: Int) -> UInt8 {
        let bitmap = Bitmap(width: canvasWidth, height: canvasHeight)
        annotation.render(in: bitmap.context)
        var minimum: UInt8 = 255
        for y in Int(rect.minY)..<Int(rect.maxY) {
            for x in Int(rect.minX)..<Int(rect.maxX) {
                minimum = min(minimum, bitmap.pixel(x: x, y: y).a)
            }
        }
        return minimum
    }

    // MARK: - 1. Blur/pixelate sample the region they cover

    func testBlurSamplesTheRegionItCoversNotTheVerticalMirror() {
        let image = redBottomBlueTopImage()
        let blur = BlurAnnotation(rect: CGRect(x: 10, y: 5, width: 80, height: 30), intensity: 2, sourceImage: image)
        let bitmap = Bitmap(width: 100, height: 100)
        bitmap.context.draw(image, in: CGRect(x: 0, y: 0, width: 100, height: 100))
        blur.render(in: bitmap.context)

        let center = bitmap.pixel(x: 50, y: 20)
        XCTAssertGreaterThan(center.r, 200, "blurred region should still be red (it covers the red half)")
        XCTAssertLessThan(center.b, 50)
    }

    func testPixelateSamplesTheRegionItCoversNotTheVerticalMirror() {
        let image = redBottomBlueTopImage()
        let pixelate = PixelateAnnotation(rect: CGRect(x: 10, y: 5, width: 80, height: 30), blockSize: 8, sourceImage: image)
        let bitmap = Bitmap(width: 100, height: 100)
        bitmap.context.draw(image, in: CGRect(x: 0, y: 0, width: 100, height: 100))
        pixelate.render(in: bitmap.context)

        let center = bitmap.pixel(x: 50, y: 20)
        XCTAssertGreaterThan(center.r, 200)
        XCTAssertLessThan(center.b, 50)
    }

    func testBlurRectPartiallyOffImageIsNotStretched() {
        // Left 20px black, rest white. A blur rect hanging 40px off the left
        // edge must keep the black/white boundary at x = 20.
        let bitmapSource = Bitmap(width: 100, height: 40)
        bitmapSource.fill(CGRect(x: 0, y: 0, width: 100, height: 40), r: 1, g: 1, b: 1)
        bitmapSource.fill(CGRect(x: 0, y: 0, width: 20, height: 40), r: 0, g: 0, b: 0)
        let image = bitmapSource.image()

        let blur = BlurAnnotation(rect: CGRect(x: -40, y: 10, width: 80, height: 20), intensity: 1, sourceImage: image)
        let bitmap = Bitmap(width: 100, height: 40)
        bitmap.context.draw(image, in: CGRect(x: 0, y: 0, width: 100, height: 40))
        blur.render(in: bitmap.context)

        XCTAssertLessThan(bitmap.pixel(x: 8, y: 20).r, 60, "x=8 is black in the source")
        XCTAssertGreaterThan(bitmap.pixel(x: 32, y: 20).r, 200, "x=32 is white in the source")
    }

    // MARK: - 2. Redaction is opaque to the edges

    func testBlurIsFullyOpaqueToItsEdges() {
        let image = solidImage(width: 200, height: 40)
        let rect = CGRect(x: 0, y: 10, width: 200, height: 20)
        let blur = BlurAnnotation(rect: rect, intensity: 10, sourceImage: image)
        XCTAssertEqual(minAlpha(of: blur, in: rect, canvasWidth: 200, canvasHeight: 40), 255)
    }

    func testPixelateIsFullyOpaqueToItsEdges() {
        let image = solidImage(width: 60, height: 40)
        let rect = CGRect(x: 3, y: 5, width: 37, height: 23)
        let pixelate = PixelateAnnotation(rect: rect, blockSize: 10, sourceImage: image)
        XCTAssertEqual(minAlpha(of: pixelate, in: rect, canvasWidth: 60, canvasHeight: 40), 255)
    }

    // MARK: - 3/4. Crop undo and pixel alignment

    func testCropDuplicatePreservesVisibility() {
        let crop = CropAnnotation(rect: CGRect(x: 0, y: 0, width: 10, height: 10))
        crop.isVisible = false
        XCTAssertFalse(crop.duplicate().isVisible)
    }

    func testUndoingCropLeavesNoHiddenCropAndExportsFullImage() {
        let state = CanvasState(image: redBottomBlueTopImage())
        let crop = CropAnnotation(rect: CGRect(x: 10.4, y: 10.6, width: 50.2, height: 40.3))
        crop.isVisible = false
        state.annotations.append(crop)

        // Edges snap to whole pixels: x 10.4...60.6 -> 10...61, y 10.6...50.9 -> 11...51.
        XCTAssertTrue(state.applyActiveCrop())
        XCTAssertEqual(state.imageWidth, 51)
        XCTAssertEqual(state.imageHeight, 40)

        state.undoManager.undo(state: state)
        XCTAssertEqual(state.imageWidth, 100)
        XCTAssertFalse(state.annotations.contains { $0 is CropAnnotation })
        let exported = state.renderFinalImage()
        XCTAssertEqual(exported?.width, 100)
        XCTAssertEqual(exported?.height, 100)

        state.undoManager.redo(state: state)
        XCTAssertEqual(state.imageWidth, 51)
        XCTAssertEqual(state.renderFinalImage()?.width, 51)
    }

    func testFractionalCropDoesNotResampleImage() {
        // Alternating 1px black/white columns: any sub-pixel offset produces
        // intermediate greys.
        let source = Bitmap(width: 40, height: 40)
        for x in 0..<40 {
            let value: CGFloat = x % 2 == 0 ? 1 : 0
            source.fill(CGRect(x: x, y: 0, width: 1, height: 40), r: value, g: value, b: value)
        }
        let state = CanvasState(image: source.image())
        state.annotations.append(CropAnnotation(rect: CGRect(x: 3.4, y: 2.6, width: 20.3, height: 20.2)))
        XCTAssertTrue(state.applyActiveCrop())

        let cropped = Bitmap(width: state.imageWidth, height: state.imageHeight)
        cropped.context.draw(state.baseImage, in: CGRect(x: 0, y: 0, width: state.imageWidth, height: state.imageHeight))
        for x in 0..<state.imageWidth {
            let red = cropped.pixel(x: x, y: state.imageHeight / 2).r
            XCTAssertTrue(red == 0 || red == 255, "column \(x) was resampled to \(red)")
        }
    }

    // MARK: - 5. Stroke-distance hit tests

    func testLineLikeShapesHitTestByStrokeDistance() {
        let start = CGPoint(x: 0, y: 0)
        let end = CGPoint(x: 100, y: 100)
        let onStroke = CGPoint(x: 50, y: 51)
        let insideBoundingBoxOnly = CGPoint(x: 90, y: 10)

        let line = LineAnnotation(start: start, end: end, color: .red, strokeWidth: 3)
        XCTAssertTrue(line.hitTest(point: onStroke))
        XCTAssertFalse(line.hitTest(point: insideBoundingBoxOnly))

        let highlighter = HighlighterAnnotation(start: start, end: end, color: .yellow, strokeWidth: 20)
        XCTAssertTrue(highlighter.hitTest(point: onStroke))
        XCTAssertFalse(highlighter.hitTest(point: insideBoundingBoxOnly))

        let pencil = PencilAnnotation(points: [start, CGPoint(x: 50, y: 50), end], color: .red, strokeWidth: 3)
        XCTAssertTrue(pencil.hitTest(point: onStroke))
        XCTAssertFalse(pencil.hitTest(point: insideBoundingBoxOnly))

        for style in ArrowStyle.allCases where style != .curved {
            let arrow = ArrowAnnotation(start: start, end: end, color: .red, strokeWidth: 3, style: style)
            XCTAssertTrue(arrow.hitTest(point: onStroke), "\(style)")
            XCTAssertTrue(arrow.hitTest(point: CGPoint(x: 98, y: 95)), "\(style) head")
            XCTAssertFalse(arrow.hitTest(point: insideBoundingBoxOnly), "\(style)")
        }
        let curved = ArrowAnnotation(start: start, end: end, color: .red, strokeWidth: 3, style: .curved)
        XCTAssertFalse(curved.hitTest(point: insideBoundingBoxOnly))
    }

    // MARK: - 6. Remove undo

    private func makeRect(_ x: CGFloat) -> RectangleAnnotation {
        RectangleAnnotation(rect: CGRect(x: x, y: 0, width: 10, height: 10), strokeColor: .red, fillColor: nil, strokeWidth: 1)
    }

    func testUndoRemoveRestoresOriginalStackingIndex() {
        let state = CanvasState(image: solidImage(width: 100, height: 100))
        let a = makeRect(0), b = makeRect(20), c = makeRect(40)
        state.annotations = [a, b, c]

        state.removeAnnotation(id: a.id)
        state.undoManager.undo(state: state)
        XCTAssertEqual(state.annotations.map(\.id), [a.id, b.id, c.id])
    }

    func testMultiDeleteIsOneUndoStep() {
        let state = CanvasState(image: solidImage(width: 100, height: 100))
        let a = makeRect(0), b = makeRect(20), c = makeRect(40), d = makeRect(60)
        state.annotations = [a, b, c, d]

        state.removeAnnotations(ids: [a.id, c.id, d.id])
        XCTAssertEqual(state.annotations.map(\.id), [b.id])
        XCTAssertEqual(state.undoManager.undoCount, 1)

        state.undoManager.undo(state: state)
        XCTAssertEqual(state.annotations.map(\.id), [a.id, b.id, c.id, d.id])

        state.undoManager.redo(state: state)
        XCTAssertEqual(state.annotations.map(\.id), [b.id])
    }

    // MARK: - 7. Coalesced option edits

    private func rect(_ source: RectangleAnnotation, width: CGFloat) -> RectangleAnnotation {
        RectangleAnnotation(id: source.id, rect: source.rect, strokeColor: source.strokeColor, fillColor: nil, strokeWidth: width)
    }

    func testContinuousOptionEditsCoalesceIntoOneUndoEntry() {
        let state = CanvasState(image: solidImage(width: 100, height: 100))
        let original = makeRect(0)
        state.addAnnotation(original)
        XCTAssertEqual(state.undoManager.undoCount, 1)

        for width in stride(from: 2.0, through: 12.0, by: 1.0) {
            state.replaceAnnotations([rect(original, width: CGFloat(width))], coalescingKey: "width")
        }
        XCTAssertEqual(state.undoManager.undoCount, 2, "slider drag should be a single entry")
        XCTAssertEqual((state.annotations.first as? RectangleAnnotation)?.strokeWidth, 12)

        state.replaceAnnotations([rect(original, width: 20)], coalescingKey: "other-control")
        XCTAssertEqual(state.undoManager.undoCount, 3, "a different control starts a new entry")

        state.undoManager.undo(state: state)
        state.undoManager.undo(state: state)
        XCTAssertEqual((state.annotations.first as? RectangleAnnotation)?.strokeWidth, 1)
    }

    func testGestureEndingWhereItStartedLeavesNoUndoEntry() {
        let state = CanvasState(image: solidImage(width: 100, height: 100))
        let original = makeRect(0)
        state.addAnnotation(original)

        // Toggle on then back off within the coalescing window.
        state.replaceAnnotations([rect(original, width: 5)], coalescingKey: "toggle")
        state.replaceAnnotations([rect(original, width: 1)], coalescingKey: "toggle")
        XCTAssertEqual(state.undoManager.undoCount, 1, "on->off should not leave a no-op entry")

        // Undo now undoes the add, i.e. it visibly does something.
        state.undoManager.undo(state: state)
        XCTAssertTrue(state.annotations.isEmpty)
    }

    func testNoOpModificationIsNotRecorded() {
        let state = CanvasState(image: solidImage(width: 100, height: 100))
        let original = makeRect(0)
        state.addAnnotation(original)
        state.replaceAnnotations([rect(original, width: 1)], coalescingKey: "width")
        XCTAssertEqual(state.undoManager.undoCount, 1)
    }

    func testUndoingCropWhileCropToolActiveResetsLiveCropToRestoredImage() {
        let state = CanvasState(image: solidImage(width: 120, height: 90))
        state.annotations.append(CropAnnotation(rect: CGRect(x: 10, y: 10, width: 50, height: 50)))
        XCTAssertTrue(state.applyActiveCrop())
        XCTAssertEqual(state.imageWidth, 50)

        // Re-entering the crop tool creates a full-image crop of the 50x50 image.
        let liveCrop = CropAnnotation(rect: CGRect(x: 0, y: 0, width: 50, height: 50))
        liveCrop.isVisible = false
        state.annotations.append(liveCrop)

        state.undoManager.undo(state: state)
        XCTAssertEqual(state.imageWidth, 120)
        XCTAssertEqual(state.imageHeight, 90)
        let crops = state.annotations.compactMap { $0 as? CropAnnotation }
        XCTAssertEqual(crops.count, 1)
        XCTAssertEqual(crops.first?.id, liveCrop.id)
        XCTAssertEqual(crops.first?.rect, CGRect(x: 0, y: 0, width: 120, height: 90))
        XCTAssertEqual(crops.first?.isVisible, false)
    }

    // MARK: - 8. Abandoned text creation

    func testDiscardLastAddDropsTheCreationStep() {
        let state = CanvasState(image: solidImage(width: 100, height: 100))
        let text = TextAnnotation(position: .zero, text: TextAnnotation.placeholderText, fontName: "Helvetica", fontSize: 16, color: .red)
        state.addAnnotation(text)
        XCTAssertTrue(state.undoManager.discardLastAdd(of: text.id))
        XCTAssertFalse(state.undoManager.canUndo)
    }

    // MARK: - 9. Rotated selection frame

    func testSelectionFrameIsUnrotatedWithSeparateRotation() {
        let rectangle = RectangleAnnotation(
            rect: CGRect(x: 10, y: 10, width: 40, height: 20),
            strokeColor: .red, fillColor: nil, strokeWidth: 1, rotationDegrees: 30
        )
        XCTAssertEqual(AnnotationGeometry.selectionFrame(for: rectangle), rectangle.rect)
        XCTAssertEqual(AnnotationGeometry.selectionRotationRadians(for: rectangle), 30 * .pi / 180, accuracy: 1e-9)
    }

    // MARK: - 10. Counter numbering

    func testNextCounterValueTracksExistingCounters() {
        XCTAssertEqual(ToolManager.nextCounterValue(in: []), 1)
        let one = CounterAnnotation(position: .zero, value: 1, style: .numbers, color: .red)
        let three = CounterAnnotation(position: .zero, value: 3, style: .numbers, color: .red)
        XCTAssertEqual(ToolManager.nextCounterValue(in: [one, three]), 4)
        XCTAssertEqual(ToolManager.nextCounterValue(in: [one]), 2)
    }
}
