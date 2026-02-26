import AppKit

enum ImageStitcher {
    static func stitch(_ images: [CGImage]) -> CGImage? {
        guard images.count >= 2 else { return images.first }

        let width = images[0].width

        // Detect overlap between consecutive images using cross-correlation on horizontal strips
        var offsets: [Int] = [0]
        for i in 1..<images.count {
            let overlap = findOverlap(top: images[i - 1], bottom: images[i])
            let yOffset = offsets.last! + images[i - 1].height - overlap
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

    private static func findOverlap(top: CGImage, bottom: CGImage) -> Int {
        let stripHeight = 40
        let searchRange = min(top.height / 2, bottom.height / 2)

        // Extract bottom strip of top image
        guard let topStrip = top.cropping(to: CGRect(x: 0, y: top.height - stripHeight, width: top.width, height: stripHeight)) else {
            return 0
        }

        let topData = pixelData(from: topStrip)

        var bestMatch = 0
        var bestScore: CGFloat = 0

        // Search through bottom image from top
        for offset in stride(from: 0, to: searchRange - stripHeight, by: 2) {
            guard let bottomStrip = bottom.cropping(to: CGRect(x: 0, y: offset, width: bottom.width, height: stripHeight)) else { continue }
            let bottomData = pixelData(from: bottomStrip)

            let score = normalizedCrossCorrelation(topData, bottomData)
            if score > bestScore && score > 0.9 {
                bestScore = score
                bestMatch = bottom.height - offset
            }
        }

        return bestMatch
    }

    private static func pixelData(from image: CGImage) -> [UInt8] {
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        var data = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let context = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return data }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return data
    }

    private static func normalizedCrossCorrelation(_ a: [UInt8], _ b: [UInt8]) -> CGFloat {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        var sum: CGFloat = 0
        var sumSqA: CGFloat = 0
        var sumSqB: CGFloat = 0
        let meanA = CGFloat(a.reduce(0, { $0 + Int($1) })) / CGFloat(a.count)
        let meanB = CGFloat(b.reduce(0, { $0 + Int($1) })) / CGFloat(b.count)

        // Sample every 4th pixel for performance
        for i in stride(from: 0, to: a.count, by: 4) {
            let da = CGFloat(a[i]) - meanA
            let db = CGFloat(b[i]) - meanB
            sum += da * db
            sumSqA += da * da
            sumSqB += db * db
        }

        let denom = sqrt(sumSqA * sumSqB)
        return denom > 0 ? sum / denom : 0
    }
}
