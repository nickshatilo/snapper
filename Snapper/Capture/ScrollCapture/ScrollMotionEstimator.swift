import AppKit

struct ScrollMotionEstimate {
    let verticalShift: Int
    let confidence: Double
}

struct ScrollMotionEstimator {
    var workingWidth: Int = 360
    var minShift: Int = 14
    var maxShiftRatio: CGFloat = 0.42
    var topInsetRatio: CGFloat = 0.14
    var bottomInsetRatio: CGFloat = 0.12
    var sideInsetRatio: CGFloat = 0.08
    var rowStride: Int = 2
    var columnStride: Int = 3

    func estimate(previous: CGImage, current: CGImage) -> ScrollMotionEstimate? {
        guard let previousFrame = preprocess(previous),
              let currentFrame = preprocess(current),
              previousFrame.width == currentFrame.width,
              previousFrame.height == currentFrame.height else {
            return nil
        }

        let width = previousFrame.width
        let height = previousFrame.height
        let xStart = max(0, Int(CGFloat(width) * sideInsetRatio))
        let xEnd = min(width, width - xStart)
        let yStart = max(0, Int(CGFloat(height) * topInsetRatio))
        let yEnd = min(height, height - Int(CGFloat(height) * bottomInsetRatio))
        let usableHeight = yEnd - yStart
        let maxShift = max(minShift + 1, min(Int(CGFloat(height) * maxShiftRatio), usableHeight - 2))

        guard xEnd - xStart >= 8, usableHeight > minShift else {
            return nil
        }

        var bestShift = 0
        var bestScore = Double.greatestFiniteMagnitude
        var secondBestScore = Double.greatestFiniteMagnitude

        for shift in minShift...maxShift {
            let score = differenceScore(
                previous: previousFrame,
                current: currentFrame,
                xStart: xStart,
                xEnd: xEnd,
                yStart: yStart,
                yEnd: yEnd,
                shift: shift
            )
            guard score.isFinite else { continue }

            if score < bestScore {
                secondBestScore = bestScore
                bestScore = score
                bestShift = shift
            } else if score < secondBestScore {
                secondBestScore = score
            }
        }

        guard bestShift > 0, bestScore.isFinite else {
            return nil
        }

        let normalizedScore = bestScore / 255.0
        let separation = secondBestScore.isFinite ? max(0, secondBestScore - bestScore) / 255.0 : 0
        let scoreComponent = max(0, min(1, 1 - normalizedScore / 0.18))
        let separationComponent = max(0, min(1, separation / 0.045))
        let confidence = (scoreComponent * 0.7) + (separationComponent * 0.3)
        let sourceShift = max(
            1,
            Int(
                (CGFloat(bestShift) * CGFloat(previous.height) / CGFloat(max(1, previousFrame.height)))
                    .rounded()
            )
        )

        return ScrollMotionEstimate(
            verticalShift: sourceShift,
            confidence: confidence
        )
    }

    private func differenceScore(
        previous: GrayFrame,
        current: GrayFrame,
        xStart: Int,
        xEnd: Int,
        yStart: Int,
        yEnd: Int,
        shift: Int
    ) -> Double {
        let sampleEnd = yEnd - shift
        guard sampleEnd > yStart else {
            return .infinity
        }

        var totalDifference = 0
        var sampleCount = 0

        for y in stride(from: yStart, to: sampleEnd, by: rowStride) {
            let previousRow = (y + shift) * previous.width
            let currentRow = y * current.width

            for x in stride(from: xStart, to: xEnd, by: columnStride) {
                totalDifference += abs(
                    Int(previous.pixels[previousRow + x]) - Int(current.pixels[currentRow + x])
                )
                sampleCount += 1
            }
        }

        guard sampleCount > 0 else {
            return .infinity
        }

        return Double(totalDifference) / Double(sampleCount)
    }

    private func preprocess(_ image: CGImage) -> GrayFrame? {
        let targetWidth = max(1, min(workingWidth, image.width))
        let scale = CGFloat(targetWidth) / CGFloat(max(1, image.width))
        let targetHeight = max(1, Int((CGFloat(image.height) * scale).rounded()))
        let bytesPerRow = targetWidth
        let byteCount = bytesPerRow * targetHeight

        guard let data = CFDataCreateMutable(nil, byteCount) else {
            return nil
        }
        CFDataSetLength(data, byteCount)
        guard let pointer = CFDataGetMutableBytePtr(data) else {
            return nil
        }

        guard let context = CGContext(
            data: pointer,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))

        return GrayFrame(
            width: targetWidth,
            height: targetHeight,
            pixels: Array(UnsafeBufferPointer(start: pointer, count: byteCount))
        )
    }
}

private struct GrayFrame {
    let width: Int
    let height: Int
    let pixels: [UInt8]
}
