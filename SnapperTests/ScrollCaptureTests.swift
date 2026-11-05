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

    // MARK: - No-motion detection

    func testScrollMotionEstimatorTreatsFlatFramesAsStationary() {
        let flat = makeSolidImage(width: 600, height: 400, gray: 240)
        let estimator = ScrollMotionEstimator()

        XCTAssertNil(estimator.estimate(previous: flat, current: flat))
        guard case .stationary = estimator.analyze(previous: flat, current: flat) else {
            XCTFail("Flat content must not be reported as motion")
            return
        }
    }

    func testScrollMotionEstimatorTreatsDuplicatedFramesAsStationary() {
        let base = makeTexturedImage(width: 600, height: 900)
        let frame = crop(base, x: 0, y: 120, width: 600, height: 400)
        let duplicate = crop(base, x: 0, y: 120, width: 600, height: 400)
        let estimator = ScrollMotionEstimator()

        XCTAssertNil(estimator.estimate(previous: frame, current: duplicate))
        guard case .stationary = estimator.analyze(previous: frame, current: duplicate) else {
            XCTFail("Identical frames must not be reported as motion")
            return
        }
    }

    func testScrollMotionEstimatorTreatsFlatBandAsAmbiguousWhenEdgesChange() {
        // Flat matching band, but the excluded top rows differ: something
        // changed that the estimator can't measure. Not "stationary" (which
        // would end a wheel-driven session) and certainly not motion.
        let previous = makeSolidImage(width: 600, height: 400, gray: 240)
        let current = overlayBand(previous, fromTop: 0, height: 30, gray: 20)
        let estimator = ScrollMotionEstimator()

        XCTAssertNil(estimator.estimate(previous: previous, current: current))
        guard case .ambiguous = estimator.analyze(previous: previous, current: current) else {
            XCTFail("Expected an ambiguous result")
            return
        }
    }

    // MARK: - Full-resolution refinement

    func testScrollMotionEstimatorRefinesShiftBelowDownscaleFactor() {
        // 1440 px wide -> 360 px working width: a 4x downscale. 61 is not a
        // multiple of 4, so only full-resolution refinement can recover it.
        let base = makeTexturedImage(width: 1440, height: 1300)
        let previous = crop(base, x: 0, y: 0, width: 1440, height: 900)
        let current = crop(base, x: 0, y: 61, width: 1440, height: 900)
        let estimator = ScrollMotionEstimator()

        guard let estimate = estimator.estimate(previous: previous, current: current) else {
            XCTFail("Expected a motion estimate")
            return
        }

        XCTAssertEqual(estimate.verticalShift, 61)
        XCTAssertGreaterThanOrEqual(estimate.confidence, 0.48)
    }

    func testEstimatedShiftsStitchSeamlessly() {
        let base = makeTexturedImage(width: 1200, height: 1400)
        let offsets = [0, 133, 271, 402]
        let frames = offsets.map { crop(base, x: 0, y: $0, width: 1200, height: 600) }
        let estimator = ScrollMotionEstimator()
        let stitcher = ScrollStitcher(initialImage: frames[0])

        for index in 1..<frames.count {
            guard let estimate = estimator.estimate(previous: frames[index - 1], current: frames[index]) else {
                XCTFail("Expected a motion estimate for frame \(index)")
                return
            }
            XCTAssertEqual(estimate.verticalShift, offsets[index] - offsets[index - 1])
            XCTAssertTrue(stitcher.append(frame: frames[index], verticalShift: estimate.verticalShift))
        }

        let expected = crop(base, x: 0, y: 0, width: 1200, height: 600 + offsets.last!)
        XCTAssertEqual(stitcher.image.height, expected.height)
        XCTAssertEqual(rgbaRows(of: stitcher.image), rgbaRows(of: expected))
    }

    // MARK: - Stitcher geometry

    func testScrollStitcherReproducesSourceRowsExactly() {
        let base = makeTexturedImage(width: 200, height: 500)
        let first = crop(base, x: 0, y: 0, width: 200, height: 180)
        let second = crop(base, x: 0, y: 37, width: 200, height: 180)
        let third = crop(base, x: 0, y: 82, width: 200, height: 180)
        let stitcher = ScrollStitcher(initialImage: first)

        XCTAssertTrue(stitcher.append(frame: second, verticalShift: 37))
        XCTAssertTrue(stitcher.append(frame: third, verticalShift: 45))
        XCTAssertEqual(stitcher.footerHeight, 0)

        let expected = crop(base, x: 0, y: 0, width: 200, height: 262)
        XCTAssertEqual(rgbaRows(of: stitcher.image), rgbaRows(of: expected))
    }

    func testScrollStitcherClampedFinalStripContinuesFromSeam() {
        let base = makeTexturedImage(width: 200, height: 500)
        let first = crop(base, x: 0, y: 0, width: 200, height: 180)
        let second = crop(base, x: 0, y: 50, width: 200, height: 180)
        let stitcher = ScrollStitcher(initialImage: first, maxHeight: 210)

        XCTAssertTrue(stitcher.append(frame: second, verticalShift: 50))
        XCTAssertTrue(stitcher.reachedMaxHeight)

        // Only 30 of the 50 new rows fit; they must be the 30 directly below
        // the seam (source rows 180..<210), not the frame's bottom 30 rows.
        let expected = crop(base, x: 0, y: 0, width: 200, height: 210)
        XCTAssertEqual(rgbaRows(of: stitcher.image), rgbaRows(of: expected))
    }

    func testScrollStitcherDrawsStickyFooterOnce() {
        let footerHeight = 20
        let base = makeTexturedImage(width: 200, height: 500)
        let frames = [0, 40, 95].map {
            overlayBand(
                crop(base, x: 0, y: $0, width: 200, height: 180),
                fromTop: 180 - footerHeight,
                height: footerHeight,
                gray: 30
            )
        }
        let stitcher = ScrollStitcher(initialImage: frames[0])

        XCTAssertTrue(stitcher.append(frame: frames[1], verticalShift: 40))
        XCTAssertTrue(stitcher.append(frame: frames[2], verticalShift: 55))
        XCTAssertEqual(stitcher.footerHeight, footerHeight)

        let composite = stitcher.image
        XCTAssertEqual(composite.height, 180 + 95)

        // Body: the content hidden behind the footer in earlier frames is
        // present, with no repeated footer bands in between...
        let bodyHeight = composite.height - footerHeight
        let compositeRows = rgbaRows(of: composite)
        let expectedBody = rgbaRows(of: crop(base, x: 0, y: 0, width: 200, height: bodyHeight))
        XCTAssertEqual(Array(compositeRows[0..<bodyHeight]), expectedBody)

        // ...and the footer appears exactly once, at the bottom.
        let footerRows = rgbaRows(of: frames[2]).suffix(footerHeight)
        XCTAssertEqual(Array(compositeRows[bodyHeight...]), Array(footerRows))
    }

    // MARK: - Helpers

    private func makeTexturedImage(width: Int, height: Int) -> CGImage {
        // Blocky coarse structure (survives the estimator's downscale) plus
        // per-pixel detail (makes every row unique at full resolution).
        func mix(_ a: Int, _ b: Int) -> UInt32 {
            var h = UInt32(truncatingIfNeeded: a &* 73_856_093) ^ UInt32(truncatingIfNeeded: b &* 19_349_663)
            h ^= h >> 13
            h = h &* 0x5BD1_E995
            h ^= h >> 15
            return h
        }

        let bytesPerRow = width * 4
        var data = [UInt8](repeating: 0, count: height * bytesPerRow)
        for y in 0..<height {
            for x in 0..<width {
                let coarse = mix(x / 9, y / 7)
                let fine = mix(x &+ 7919, y &+ 104_729)
                let index = y * bytesPerRow + x * 4
                data[index] = UInt8((coarse & 0xE0) | (fine & 0x1F))
                data[index + 1] = UInt8(((coarse >> 8) & 0xE0) | ((fine >> 5) & 0x1F))
                data[index + 2] = UInt8(((coarse >> 16) & 0xE0) | ((fine >> 10) & 0x1F))
                data[index + 3] = 255
            }
        }
        return makeImage(width: width, height: height, rgba: data)
    }

    private func makeSolidImage(width: Int, height: Int, gray: UInt8) -> CGImage {
        var data = [UInt8](repeating: gray, count: width * height * 4)
        for index in stride(from: 3, to: data.count, by: 4) {
            data[index] = 255
        }
        return makeImage(width: width, height: height, rgba: data)
    }

    private func makeImage(width: Int, height: Int, rgba: [UInt8]) -> CGImage {
        let provider = CGDataProvider(data: Data(rgba) as CFData)!
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }

    /// Paints a solid band `fromTop` rows below the visual top of the image.
    private func overlayBand(_ image: CGImage, fromTop: Int, height: Int, gray: CGFloat) -> CGImage {
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.setFillColor(CGColor(red: gray / 255, green: gray / 255, blue: gray / 255, alpha: 1))
        // CG space is bottom-left: visual row `fromTop` starts at y = height - fromTop.
        context.fill(CGRect(x: 0, y: image.height - fromTop - height, width: image.width, height: height))
        return context.makeImage() ?? image
    }

    /// RGBA rows top-to-bottom, rendered into a fixed layout for comparison.
    private func rgbaRows(of image: CGImage) -> [[UInt8]] {
        let bytesPerRow = image.width * 4
        var data = [UInt8](repeating: 0, count: bytesPerRow * image.height)
        data.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return (0..<image.height).map { row in
            Array(data[(row * bytesPerRow)..<((row + 1) * bytesPerRow)])
        }
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
