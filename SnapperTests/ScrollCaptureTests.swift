import CoreGraphics
import XCTest
@testable import Snapper

final class ScrollCaptureTests: XCTestCase {
    func testScrollMotionEstimatorDetectsVerticalShift() {
        let base = makePatternImage(width: 280, height: 720)
        let previous = crop(base, x: 0, y: 0, width: 280, height: 240)
        let current = crop(base, x: 0, y: 70, width: 280, height: 240)
        let estimator = ScrollMotionEstimator()

        guard let estimate = estimator.estimate(previous: previous, current: current) else {
            XCTFail("Expected a motion estimate")
            return
        }

        XCTAssertEqual(estimate.verticalShift, 70, accuracy: 8)
        XCTAssertGreaterThan(estimate.confidence, 0.45)
    }

    func testScrollMotionEstimatorIgnoresStickyHeaderBias() {
        let base = makePatternImage(width: 280, height: 720)
        let previous = overlayStickyHeader(
            crop(base, x: 0, y: 0, width: 280, height: 240),
            height: 32
        )
        let current = overlayStickyHeader(
            crop(base, x: 0, y: 64, width: 280, height: 240),
            height: 32
        )
        let estimator = ScrollMotionEstimator()

        guard let estimate = estimator.estimate(previous: previous, current: current) else {
            XCTFail("Expected a motion estimate")
            return
        }

        XCTAssertEqual(estimate.verticalShift, 64, accuracy: 8)
        XCTAssertGreaterThan(estimate.confidence, 0.40)
    }

    func testScrollStitcherAppendsNewBottomStrip() {
        let base = makePatternImage(width: 220, height: 520)
        let first = crop(base, x: 0, y: 0, width: 220, height: 180)
        let second = crop(base, x: 0, y: 55, width: 220, height: 180)
        let stitcher = ScrollStitcher(initialImage: first)

        XCTAssertTrue(stitcher.append(frame: second, verticalShift: 55))
        XCTAssertEqual(stitcher.image.width, 220)
        XCTAssertEqual(stitcher.image.height, 235)
        XCTAssertEqual(stitcher.appendedHeight, 55)
    }

    private func makePatternImage(width: Int, height: Int) -> CGImage {
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var data = [UInt8](repeating: 0, count: height * bytesPerRow)

        for y in 0..<height {
            for x in 0..<width {
                let index = y * bytesPerRow + (x * bytesPerPixel)
                let base = UInt8((y * 37 + x * 13) % 255)
                data[index] = base
                data[index + 1] = UInt8((y * 19 + x * 7) % 255)
                data[index + 2] = UInt8((y * 11 + x * 23) % 255)
                data[index + 3] = 255
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let provider = CGDataProvider(data: Data(data) as CFData)!
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }

    private func crop(_ image: CGImage, x: Int, y: Int, width: Int, height: Int) -> CGImage {
        image.cropping(to: CGRect(x: x, y: y, width: width, height: height))!
    }

    private func overlayStickyHeader(_ image: CGImage, height: Int) -> CGImage {
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }

        // Draw upright (no CTM flip — CGContext.draw under a flipped transform
        // mirrors the image) and paint the header over the visual top rows,
        // which in CG bottom-left space is the high-y band.
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.setFillColor(CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: image.height - height, width: image.width, height: height))
        return context.makeImage() ?? image
    }
}
