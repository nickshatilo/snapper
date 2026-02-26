import AppKit

enum ImageStitcher {
    static func stitch(_ images: [CGImage]) -> CGImage? {
        guard images.count >= 2 else { return images.first }

        let width = images[0].width
        let rowSignatures = images.map { luminanceRowMeans(from: $0) }

        var offsets: [Int] = [0]
        for i in 1..<images.count {
            let overlap = findOverlap(
                top: images[i - 1],
                bottom: images[i],
                topRows: rowSignatures[i - 1],
                bottomRows: rowSignatures[i]
            )
            let maxSafeOverlap = max(0, min(images[i - 1].height, images[i].height) - 1)
            let safeOverlap = min(max(0, overlap), maxSafeOverlap)
            let yOffset = max(0, offsets.last! + images[i - 1].height - safeOverlap)
            offsets.append(yOffset)
        }

        let totalHeight = offsets.last! + images.last!.height

        guard let context = CGContext(
            data: nil,
            width: width,
            height: totalHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: images[0].colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Draw images from bottom to top (since CGContext origin is bottom-left)
        for (i, image) in images.enumerated() {
            let y = totalHeight - offsets[i] - image.height
            context.draw(image, in: CGRect(x: 0, y: y, width: image.width, height: image.height))
        }

        return context.makeImage()
    }

    private static func findOverlap(
        top: CGImage,
        bottom: CGImage,
        topRows: [Float]?,
        bottomRows: [Float]?
    ) -> Int {
        guard let topRows, let bottomRows else { return 0 }

        let maxOverlap = min(top.height / 2, bottom.height / 2, topRows.count, bottomRows.count)
        let stripHeight = min(64, maxOverlap)
        guard stripHeight >= 16 else { return 0 }

        let searchLimit = maxOverlap - stripHeight
        guard searchLimit >= 0 else {
            return 0
        }

        let topStripStart = topRows.count - stripHeight
        let topStrip = Array(topRows[topStripStart..<topRows.count])

        var bestMatch = 0
        var bestScore: CGFloat = 0.0

        for offset in stride(from: 0, through: searchLimit, by: 2) {
            let bottomStrip = Array(bottomRows[offset..<(offset + stripHeight)])
            let score = normalizedCrossCorrelation(topStrip, bottomStrip)
            if score > bestScore {
                bestScore = score
                bestMatch = offset + stripHeight
            }
        }

        guard bestScore >= 0.88 else { return 0 }
        return bestMatch
    }

    private static func luminanceRowMeans(from image: CGImage, sampleWidth: Int = 256) -> [Float]? {
        let width = min(sampleWidth, max(1, image.width))
        let height = max(1, image.height)
        var data = [UInt8](repeating: 0, count: width * height)

        guard let context = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        context.interpolationQuality = .low
        context.setShouldAntialias(false)
        // Keep row order stable for overlap detection.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var means = [Float](repeating: 0, count: height)
        for y in 0..<height {
            let rowStart = y * width
            var sum = 0
            for x in 0..<width {
                sum += Int(data[rowStart + x])
            }
            means[y] = Float(sum) / Float(width)
        }

        return means
    }

    private static func normalizedCrossCorrelation(_ a: [Float], _ b: [Float]) -> CGFloat {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        let meanA = Double(a.reduce(0, +)) / Double(a.count)
        let meanB = Double(b.reduce(0, +)) / Double(b.count)

        var sum = 0.0
        var sumSqA = 0.0
        var sumSqB = 0.0

        for i in 0..<a.count {
            let da = Double(a[i]) - meanA
            let db = Double(b[i]) - meanB
            sum += da * db
            sumSqA += da * da
            sumSqB += db * db
        }

        let denom = sqrt(sumSqA * sumSqB)
        return denom > 0 ? CGFloat(sum / denom) : 0
    }
}
