import AppKit

final class ScrollStitcher {
    /// Hard ceiling on the stitched output height (pixels) so endless feeds
    /// can't grow memory without bound.
    let maxHeight: Int

    private let initialImage: CGImage
    private var strips: [CGImage] = []
    private(set) var appendedHeight: Int = 0

    init(initialImage: CGImage, maxHeight: Int = 20_000) {
        self.initialImage = initialImage
        self.maxHeight = maxHeight
    }

    var hasAppendedContent: Bool {
        appendedHeight > 0
    }

    var currentHeight: Int {
        initialImage.height + appendedHeight
    }

    var reachedMaxHeight: Bool {
        currentHeight >= maxHeight
    }

    var image: CGImage {
        makeImage() ?? initialImage
    }

    @discardableResult
    func append(frame: CGImage, verticalShift: Int) -> Bool {
        guard frame.width == initialImage.width, !reachedMaxHeight else {
            return false
        }

        let headroom = maxHeight - currentHeight
        let newContentHeight = max(0, min(min(verticalShift, frame.height - 1), headroom))
        guard newContentHeight >= 4 else {
            return false
        }

        let stripRect = CGRect(
            x: 0,
            y: frame.height - newContentHeight,
            width: frame.width,
            height: newContentHeight
        ).integral

        // Copy the strip into its own backing store; a bare cropping(to:)
        // would keep the entire source frame alive for the session.
        guard let strip = copyStrip(from: frame, rect: stripRect) else {
            return false
        }

        strips.append(strip)
        appendedHeight += strip.height
        return true
    }

    private func copyStrip(from frame: CGImage, rect: CGRect) -> CGImage? {
        guard let cropped = frame.cropping(to: rect),
              let context = CGContext(
                data: nil,
                width: cropped.width,
                height: cropped.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: frame.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }
        context.interpolationQuality = .none
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: cropped.width, height: cropped.height))
        return context.makeImage()
    }

    /// Composites the initial frame plus all appended strips top-to-bottom.
    /// Positions are computed in native CG space (bottom-left origin) with no
    /// flip transform, so every segment renders upright.
    private func makeImage() -> CGImage? {
        guard hasAppendedContent else { return initialImage }

        let totalHeight = currentHeight
        guard let context = CGContext(
            data: nil,
            width: initialImage.width,
            height: totalHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: initialImage.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high

        var segmentTop = totalHeight
        for segment in [initialImage] + strips {
            context.draw(
                segment,
                in: CGRect(
                    x: 0,
                    y: segmentTop - segment.height,
                    width: segment.width,
                    height: segment.height
                )
            )
            segmentTop -= segment.height
        }

        return context.makeImage()
    }
}
