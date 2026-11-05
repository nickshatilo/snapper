import AppKit

struct ScrollMotionEstimate {
    let verticalShift: Int
    let confidence: Double
}

/// Result of comparing a frame against the last accepted frame.
enum ScrollMotionAnalysis {
    /// Content moved up by `verticalShift` source pixels.
    case moved(ScrollMotionEstimate)
    /// The frames are effectively identical: nothing scrolled.
    case stationary
    /// Something changed, but no downward shift explains it clearly better
    /// than "no motion" (flat content, animation, overshoot past the window).
    case ambiguous
}

struct ScrollMotionEstimator {
    var workingWidth: Int = 360
    var minShift: Int = 1
    var maxShiftRatio: CGFloat = 0.42
    var topInsetRatio: CGFloat = 0.14
    var bottomInsetRatio: CGFloat = 0.12
    var sideInsetRatio: CGFloat = 0.08
    var rowStride: Int = 2
    var columnStride: Int = 3
    /// Mean absolute gray difference at or below which two frames count as
    /// identical (no motion).
    var stationaryThreshold: Double = 1.5
    /// A shift is only accepted when it cuts the no-motion difference to at
    /// most this fraction...
    var maxScoreRatioVsStationary: Double = 0.5
    /// ...and by at least this many gray levels.
    var minImprovementOverStationary: Double = 4.0
    /// Columns sampled per row during full-resolution refinement.
    var refinementColumns: Int = 480

    func estimate(previous: CGImage, current: CGImage) -> ScrollMotionEstimate? {
        if case let .moved(estimate) = analyze(previous: previous, current: current) {
            return estimate
        }
        return nil
    }

    func analyze(previous: CGImage, current: CGImage) -> ScrollMotionAnalysis {
        guard let previousFrame = makeGrayFrame(previous, targetWidth: min(workingWidth, previous.width)),
              let currentFrame = makeGrayFrame(current, targetWidth: min(workingWidth, current.width)),
              previousFrame.width == currentFrame.width,
              previousFrame.height == currentFrame.height,
              let band = matchingBand(width: previousFrame.width, height: previousFrame.height) else {
            return .ambiguous
        }

        let usableHeight = band.yEnd - band.yStart
        let maxShift = max(minShift + 1, min(Int(CGFloat(previousFrame.height) * maxShiftRatio), usableHeight - 2))

        // "No motion" is always a candidate: a shift only wins if it explains
        // the frames meaningfully better than leaving them where they were.
        let stationaryScore = differenceScore(
            previous: previousFrame, current: currentFrame, band: band,
            shift: 0, rowStride: rowStride, columnStride: columnStride
        )

        var bestShift = 0
        var bestScore = Double.greatestFiniteMagnitude
        var secondBestScore = Double.greatestFiniteMagnitude

        for shift in minShift...maxShift {
            let score = differenceScore(
                previous: previousFrame, current: currentFrame, band: band,
                shift: shift, rowStride: rowStride, columnStride: columnStride
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

        let beatsStationary = bestShift > 0
            && bestScore.isFinite
            && stationaryScore.isFinite
            && stationaryScore - bestScore >= minImprovementOverStationary
            && bestScore <= stationaryScore * maxScoreRatioVsStationary
        guard beatsStationary else {
            // Distinguish "nothing changed" from "changed, but unmeasurable"
            // (e.g. a flat band while content outside it moved).
            let wholeFrame = MatchingBand(xStart: 0, xEnd: previousFrame.width, yStart: 0, yEnd: previousFrame.height)
            let wholeFrameScore = differenceScore(
                previous: previousFrame, current: currentFrame, band: wholeFrame,
                shift: 0, rowStride: rowStride, columnStride: columnStride
            )
            return stationaryScore <= stationaryThreshold && wholeFrameScore <= stationaryThreshold
                ? .stationary
                : .ambiguous
        }

        let normalizedScore = bestScore / 255.0
        let separation = secondBestScore.isFinite ? max(0, secondBestScore - bestScore) / 255.0 : 0
        let scoreComponent = max(0, min(1, 1 - normalizedScore / 0.18))
        let separationComponent = max(0, min(1, separation / 0.045))
        let confidence = (scoreComponent * 0.7) + (separationComponent * 0.3)

        let sourceShift = refineShift(
            previous: previous,
            current: current,
            coarseShift: bestShift,
            coarseHeight: previousFrame.height
        )

        return .moved(ScrollMotionEstimate(
            verticalShift: sourceShift,
            confidence: confidence
        ))
    }

    /// The coarse search runs on a downscaled frame, so its shift is only
    /// accurate to one working pixel (several source pixels on Retina).
    /// Re-search a small window around it at full resolution so seams land
    /// on the exact row.
    private func refineShift(previous: CGImage, current: CGImage, coarseShift: Int, coarseHeight: Int) -> Int {
        let scale = CGFloat(previous.height) / CGFloat(max(1, coarseHeight))
        let coarseSourceShift = max(1, Int((CGFloat(coarseShift) * scale).rounded()))
        guard scale > 1.01,
              let previousFull = makeGrayFrame(previous, targetWidth: previous.width),
              let currentFull = makeGrayFrame(current, targetWidth: current.width),
              previousFull.width == currentFull.width,
              previousFull.height == currentFull.height,
              let band = matchingBand(width: previousFull.width, height: previousFull.height) else {
            return coarseSourceShift
        }

        let radius = Int(scale.rounded(.up)) + 1
        let lowerShift = max(1, coarseSourceShift - radius)
        let upperShift = min(coarseSourceShift + radius, band.yEnd - band.yStart - 1)
        guard lowerShift <= upperShift else { return coarseSourceShift }

        let fullColumnStride = max(1, previousFull.width / max(1, refinementColumns))
        var bestShift = coarseSourceShift
        var bestScore = Double.greatestFiniteMagnitude
        for shift in lowerShift...upperShift {
            let score = differenceScore(
                previous: previousFull, current: currentFull, band: band,
                shift: shift, rowStride: 2, columnStride: fullColumnStride
            )
            if score < bestScore {
                bestScore = score
                bestShift = shift
            }
        }
        return bestShift
    }

    private func matchingBand(width: Int, height: Int) -> MatchingBand? {
        let xStart = max(0, Int(CGFloat(width) * sideInsetRatio))
        let xEnd = min(width, width - xStart)
        let yStart = max(0, Int(CGFloat(height) * topInsetRatio))
        let yEnd = min(height, height - Int(CGFloat(height) * bottomInsetRatio))
        guard xEnd - xStart >= 8, yEnd - yStart > minShift else {
            return nil
        }
        return MatchingBand(xStart: xStart, xEnd: xEnd, yStart: yStart, yEnd: yEnd)
    }

    private func differenceScore(
        previous: GrayFrame,
        current: GrayFrame,
        band: MatchingBand,
        shift: Int,
        rowStride: Int,
        columnStride: Int
    ) -> Double {
        let sampleEnd = band.yEnd - shift
        guard sampleEnd > band.yStart else {
            return .infinity
        }

        var totalDifference = 0
        var sampleCount = 0

        previous.pixels.withUnsafeBufferPointer { previousPixels in
            current.pixels.withUnsafeBufferPointer { currentPixels in
                for y in stride(from: band.yStart, to: sampleEnd, by: rowStride) {
                    let previousRow = (y + shift) * previous.width
                    let currentRow = y * current.width

                    for x in stride(from: band.xStart, to: band.xEnd, by: columnStride) {
                        totalDifference += abs(
                            Int(previousPixels[previousRow + x]) - Int(currentPixels[currentRow + x])
                        )
                        sampleCount += 1
                    }
                }
            }
        }

        guard sampleCount > 0 else {
            return .infinity
        }

        return Double(totalDifference) / Double(sampleCount)
    }

    private func makeGrayFrame(_ image: CGImage, targetWidth requestedWidth: Int) -> GrayFrame? {
        let targetWidth = max(1, min(requestedWidth, image.width))
        let scale = CGFloat(targetWidth) / CGFloat(max(1, image.width))
        let targetHeight = max(1, Int((CGFloat(image.height) * scale).rounded()))
        let bytesPerRow = targetWidth
        let byteCount = bytesPerRow * targetHeight

        var pixels = [UInt8](repeating: 0, count: byteCount)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: targetWidth,
                height: targetHeight,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else {
                return false
            }
            context.interpolationQuality = targetWidth == image.width ? .none : .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
            return true
        }
        guard drawn else { return nil }

        return GrayFrame(width: targetWidth, height: targetHeight, pixels: pixels)
    }
}

private struct MatchingBand {
    let xStart: Int
    let xEnd: Int
    let yStart: Int
    let yEnd: Int
}

private struct GrayFrame {
    let width: Int
    let height: Int
    let pixels: [UInt8]
}
