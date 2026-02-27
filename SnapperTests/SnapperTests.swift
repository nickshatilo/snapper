import XCTest
import CoreGraphics
import AppKit
@testable import Snapper

final class SnapperTests: XCTestCase {
    func testCaptureModeCases() {
        XCTAssertEqual(CaptureMode.allCases.count, 5)
        XCTAssertEqual(CaptureMode.fullscreen.displayName, "Fullscreen")
    }

    func testImageFormatExtensions() {
        XCTAssertEqual(ImageFormat.png.fileExtension, "png")
        XCTAssertEqual(ImageFormat.jpeg.fileExtension, "jpeg")
        XCTAssertEqual(ImageFormat.tiff.fileExtension, "tiff")
    }

    func testCaptureSoundIncludesCameraShot() {
        XCTAssertTrue(CaptureSound.allCases.contains(.cameraShot))
        XCTAssertEqual(CaptureSound.cameraShot.displayName, "Camera Shot")
        XCTAssertEqual(CaptureSound.cameraShot.nsSoundName, NSSound.Name("PhotoShutter"))
    }

    func testToolTypeShortcuts() {
        XCTAssertEqual(ToolType.arrow.shortcutKey, "A")
        XCTAssertEqual(ToolType.ocr.shortcutKey, "O")
        XCTAssertEqual(ToolType.rectangle.shortcutKey, "R")
        XCTAssertEqual(ToolType.crop.shortcutKey, "C")
        XCTAssertEqual(ToolType.allCases.count, 15)
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

    func testRenderFinalImageCropUsesAnnotationCoordinateSpace() {
        let baseImage = makeSolidRGBAImage(width: 100, height: 100, red: 255, green: 255, blue: 255)
        let state = CanvasState(image: baseImage)
        let targetRect = CGRect(x: 10, y: 70, width: 20, height: 20)

        let marker = RectangleAnnotation(
            rect: targetRect,
            strokeColor: .red,
            fillColor: .red,
            strokeWidth: 1
        )
        state.annotations.append(marker)
        state.annotations.append(CropAnnotation(rect: targetRect))

        guard let output = state.renderFinalImage() else {
            XCTFail("Expected rendered image")
            return
        }

        XCTAssertEqual(output.width, 20)
        XCTAssertEqual(output.height, 20)

        let center = rgbaPixel(in: output, x: output.width / 2, y: output.height / 2)
        XCTAssertGreaterThan(center.r, 200)
        XCTAssertLessThan(center.g, 80)
        XCTAssertLessThan(center.b, 80)
    }

    func testApplyActiveCropTransformsCanvasAndAnnotations() {
        let baseImage = makeSolidRGBAImage(width: 100, height: 80, red: 255, green: 255, blue: 255)
        let state = CanvasState(image: baseImage)

        let text = TextAnnotation(
            position: CGPoint(x: 20, y: 18),
            text: "A",
            fontName: "Helvetica",
            fontSize: 12,
            color: .red
        )
        state.annotations.append(text)
        state.annotations.append(CropAnnotation(rect: CGRect(x: 10, y: 8, width: 30, height: 20)))

        XCTAssertTrue(state.applyActiveCrop())
        XCTAssertEqual(state.imageWidth, 30)
        XCTAssertEqual(state.imageHeight, 20)
        XCTAssertFalse(state.annotations.contains { $0 is CropAnnotation })

        guard let movedText = state.annotations.first(where: { $0.id == text.id }) as? TextAnnotation else {
            XCTFail("Expected text annotation to remain after crop")
            return
        }

        XCTAssertEqual(Double(movedText.position.x), 10, accuracy: 0.01)
        XCTAssertEqual(Double(movedText.position.y), 10, accuracy: 0.01)
    }

    func testApplyActiveCropSupportsUndoRedo() {
        let baseImage = makeSolidRGBAImage(width: 120, height: 90, red: 255, green: 255, blue: 255)
        let state = CanvasState(image: baseImage)

        let rectangle = RectangleAnnotation(
            rect: CGRect(x: 40, y: 30, width: 20, height: 10),
            strokeColor: .red,
            fillColor: nil,
            strokeWidth: 2
        )
        let crop = CropAnnotation(rect: CGRect(x: 20, y: 10, width: 50, height: 40))
        state.annotations = [rectangle, crop]

        XCTAssertTrue(state.applyActiveCrop())
        XCTAssertEqual(state.imageWidth, 50)
        XCTAssertEqual(state.imageHeight, 40)
        XCTAssertFalse(state.annotations.contains { $0 is CropAnnotation })

        state.undoManager.undo(state: state)
        XCTAssertEqual(state.imageWidth, 120)
        XCTAssertEqual(state.imageHeight, 90)
        XCTAssertTrue(state.annotations.contains { $0.id == rectangle.id })
        XCTAssertTrue(state.annotations.contains { $0.id == crop.id })

        state.undoManager.redo(state: state)
        XCTAssertEqual(state.imageWidth, 50)
        XCTAssertEqual(state.imageHeight, 40)
        XCTAssertFalse(state.annotations.contains { $0 is CropAnnotation })
    }

    func testTextAnnotationSupportsRotationAndPreservesProperties() {
        let text = TextAnnotation(
            position: CGPoint(x: 24, y: 12),
            text: "Rotate Me",
            fontName: "Helvetica",
            fontSize: 14,
            color: .red
        )
        text.isBold = true
        text.hasBackground = true

        XCTAssertTrue(AnnotationGeometry.supportsRotation(text))

        guard let rotated = AnnotationGeometry.rotated(text, to: 37) as? TextAnnotation else {
            XCTFail("Expected rotated text annotation")
            return
        }

        XCTAssertEqual(Double(rotated.rotationDegrees), 37, accuracy: 0.001)
        XCTAssertEqual(rotated.text, text.text)
        XCTAssertEqual(rotated.fontName, text.fontName)
        XCTAssertEqual(Double(rotated.fontSize), Double(text.fontSize), accuracy: 0.001)
        XCTAssertEqual(rotated.hasBackground, text.hasBackground)
        XCTAssertEqual(rotated.isBold, text.isBold)

        guard let moved = AnnotationGeometry.translated(rotated, by: CGPoint(x: 11, y: -3)) as? TextAnnotation else {
            XCTFail("Expected translated text annotation")
            return
        }

        XCTAssertEqual(Double(moved.position.x), Double(rotated.position.x + 11), accuracy: 0.001)
        XCTAssertEqual(Double(moved.position.y), Double(rotated.position.y - 3), accuracy: 0.001)
        XCTAssertEqual(Double(moved.rotationDegrees), Double(rotated.rotationDegrees), accuracy: 0.001)
    }

    func testPencilAnnotationSupportsRotation() {
        let pencil = PencilAnnotation(
            points: [
                CGPoint(x: 10, y: 10),
                CGPoint(x: 30, y: 22),
                CGPoint(x: 44, y: 36),
            ],
            color: .red,
            strokeWidth: 2
        )

        XCTAssertTrue(AnnotationGeometry.supportsRotation(pencil))

        guard let rotated = AnnotationGeometry.rotated(pencil, to: 90) as? PencilAnnotation else {
            XCTFail("Expected rotated pencil annotation")
            return
        }

        XCTAssertEqual(rotated.points.count, pencil.points.count)
        XCTAssertEqual(rotated.color, pencil.color)
        XCTAssertEqual(Double(rotated.strokeWidth), Double(pencil.strokeWidth), accuracy: 0.001)
        XCTAssertGreaterThan(abs(rotated.points[0].x - pencil.points[0].x), 0.001)
        XCTAssertGreaterThan(abs(rotated.points[0].y - pencil.points[0].y), 0.001)
    }

    func testBringAnnotationToFrontSupportsUndoRedo() {
        let baseImage = makeSolidRGBAImage(width: 120, height: 90, red: 255, green: 255, blue: 255)
        let state = CanvasState(image: baseImage)

        let first = RectangleAnnotation(
            rect: CGRect(x: 10, y: 10, width: 10, height: 10),
            strokeColor: .red,
            fillColor: nil,
            strokeWidth: 1
        )
        first.zOrder = 1
        let second = RectangleAnnotation(
            rect: CGRect(x: 30, y: 10, width: 10, height: 10),
            strokeColor: .green,
            fillColor: nil,
            strokeWidth: 1
        )
        second.zOrder = 2
        let third = RectangleAnnotation(
            rect: CGRect(x: 50, y: 10, width: 10, height: 10),
            strokeColor: .blue,
            fillColor: nil,
            strokeWidth: 1
        )
        third.zOrder = 3

        state.annotations = [first, second, third]
        let initialOrder = state.annotations.map { $0.id }

        XCTAssertTrue(state.bringAnnotationToFront(id: second.id))
        XCTAssertEqual(state.selectedAnnotationID, second.id)
        XCTAssertEqual(state.annotations.last?.id, second.id)
        XCTAssertEqual(state.annotations.map { $0.id }, [first.id, third.id, second.id])
        XCTAssertGreaterThan(second.zOrder, third.zOrder)

        state.undoManager.undo(state: state)
        XCTAssertEqual(state.annotations.map { $0.id }, initialOrder)

        state.undoManager.redo(state: state)
        XCTAssertEqual(state.annotations.map { $0.id }, [first.id, third.id, second.id])
    }

    func testToolManagerMouseUpReturnsCommittedAnnotationID() {
        let image = makeSolidRGBAImage(width: 80, height: 60, red: 255, green: 255, blue: 255)
        let canvasState = CanvasState(image: image)
        let toolManager = ToolManager()
        toolManager.currentTool = .rectangle

        toolManager.mouseDown(at: CGPoint(x: 10, y: 10), canvasState: canvasState)
        toolManager.mouseDragged(to: CGPoint(x: 30, y: 30), canvasState: canvasState)
        let committedID = toolManager.mouseUp(at: CGPoint(x: 30, y: 30), canvasState: canvasState)

        XCTAssertNotNil(committedID)
        XCTAssertEqual(canvasState.selectedAnnotationID, committedID)
        XCTAssertTrue(canvasState.annotations.contains { $0.id == committedID })
    }

    func testToolManagerCropDragDoesNotCreateCropAnnotation() {
        let image = makeSolidRGBAImage(width: 120, height: 90, red: 255, green: 255, blue: 255)
        let canvasState = CanvasState(image: image)
        let toolManager = ToolManager()
        toolManager.currentTool = .crop

        toolManager.mouseDown(at: CGPoint(x: 10, y: 10), canvasState: canvasState)
        toolManager.mouseDragged(to: CGPoint(x: 60, y: 40), canvasState: canvasState)
        let committedID = toolManager.mouseUp(at: CGPoint(x: 60, y: 40), canvasState: canvasState)

        XCTAssertNil(committedID)
        XCTAssertFalse(canvasState.annotations.contains { $0 is CropAnnotation })
    }

    func testToolManagerMouseDraggedSelectsActiveAnnotation() {
        let image = makeSolidRGBAImage(width: 120, height: 90, red: 255, green: 255, blue: 255)
        let canvasState = CanvasState(image: image)
        let toolManager = ToolManager()
        toolManager.currentTool = .rectangle

        toolManager.mouseDown(at: CGPoint(x: 10, y: 10), canvasState: canvasState)
        toolManager.mouseDragged(to: CGPoint(x: 60, y: 40), canvasState: canvasState)

        guard let selectedID = canvasState.selectedAnnotationID else {
            XCTFail("Expected active dragged annotation to be selected")
            return
        }

        XCTAssertTrue(canvasState.annotations.contains { $0.id == selectedID })
    }

    private func makePatternImage(width: Int, height: Int) -> CGImage {
        var data = [UInt8](repeating: 0, count: width * height)
        var seed: UInt32 = 0x1234ABCD
        for y in 0..<height {
            seed = seed &* 1664525 &+ 1013904223
            let value = UInt8((seed >> 24) & 0xFF)
            let rowStart = y * width
            for x in 0..<width {
                data[rowStart + x] = value
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceGray()
        let context = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        return context.makeImage()!
    }

    private func makeVerticalGradientImage(width: Int, height: Int) -> CGImage {
        var data = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            let value = UInt8((Double(y) / Double(max(1, height - 1)) * 255.0).rounded())
            let rowStart = y * width
            for x in 0..<width {
                data[rowStart + x] = value
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceGray()
        let context = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        return context.makeImage()!
    }

    private func makeSolidRGBAImage(
        width: Int,
        height: Int,
        red: UInt8,
        green: UInt8,
        blue: UInt8
    ) -> CGImage {
        var data = [UInt8](repeating: 0, count: width * height * 4)
        for i in stride(from: 0, to: data.count, by: 4) {
            data[i] = red
            data[i + 1] = green
            data[i + 2] = blue
            data[i + 3] = 255
        }

        let context = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return context.makeImage()!
    }

    private func extractFrame(from source: CGImage, originY: Int, height: Int) -> CGImage {
        let targetHeight = max(1, min(height, source.height))
        let clampedOrigin = max(0, min(originY, source.height - targetHeight))
        let context = CGContext(
            data: nil,
            width: source.width,
            height: targetHeight,
            bitsPerComponent: source.bitsPerComponent,
            bytesPerRow: 0,
            space: source.colorSpace ?? CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        context.translateBy(x: 0, y: -CGFloat(clampedOrigin))
        context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
        return context.makeImage()!
    }

    private func rgbaPixel(in image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let width = image.width
        let height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let clampedX = max(0, min(x, width - 1))
        let clampedY = max(0, min(y, height - 1))
        let idx = (clampedY * width + clampedX) * 4
        return (data[idx], data[idx + 1], data[idx + 2], data[idx + 3])
    }
}
