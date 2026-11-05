import AppKit

final class ScrollStitcher {
    /// Hard ceiling on the stitched output height (pixels) so endless feeds
    /// can't grow memory without bound.
    let maxHeight: Int
    /// Largest bottom band, as a fraction of the frame height, that can be
    /// treated as a pinned footer.
    let maxFooterRatio: Double

    private let initialImage: CGImage
    /// Rows of the initial frame that belong to the scrolling body (the
    /// initial frame minus any pinned footer found on the first append).
    private var initialBodyHeight: Int
    private var strips: [CGImage] = []
    private(set) var appendedHeight: Int = 0

    /// Bottom rows that stayed pixel-identical across every accepted frame
    /// (a sticky footer, cookie bar, composer...). They are kept out of the
    /// strips and drawn once, at the very bottom of the composite.
    private(set) var footerHeight: Int = 0
    private var footer: CGImage?
    private var lastBottomBand: BottomRowBand?

    init(initialImage: CGImage, maxHeight: Int = 20_000, maxFooterRatio: Double = 0.25) {
        self.initialImage = initialImage
        self.maxHeight = maxHeight
        self.maxFooterRatio = maxFooterRatio
        self.initialBodyHeight = initialImage.height
        self.lastBottomBand = BottomRowBand(image: initialImage, rows: Self.footerSearchRows(height: initialImage.height, ratio: maxFooterRatio))
    }

    var hasAppendedContent: Bool {
        appendedHeight > 0
    }

    var currentHeight: Int {
        initialBodyHeight + appendedHeight + footerHeight
    }

    var reachedMaxHeight: Bool {
        currentHeight >= maxHeight
    }

    var image: CGImage {
        makeImage() ?? initialImage
    }

    /// Appends the content revealed by `frame`, which shows the same content
    /// as the last accepted frame moved up by `verticalShift` pixels.
    ///
    /// Footer handling: rows at the bottom that are byte-identical to the
    /// last accepted frame are excluded from the strip (exact matches only).
    /// This is safe even when those rows are ordinary flat content rather
    /// than a pinned bar: the strip always starts right where the composite's
    /// body ended, and the excluded rows are restored from the latest frame
    /// as the final footer.
    @discardableResult
    func append(frame: CGImage, verticalShift: Int) -> Bool {
        guard frame.width == initialImage.width,
              frame.height == initialImage.height,
              !reachedMaxHeight else {
            return false
        }

        let frameHeight = frame.height
        let currentBand = BottomRowBand(image: frame, rows: Self.footerSearchRows(height: frameHeight, ratio: maxFooterRatio))
        let matchingRows: Int
        if let currentBand, let lastBottomBand {
            matchingRows = currentBand.matchingBottomRows(with: lastBottomBand)
        } else {
            matchingRows = 0
        }

        // On the first append the footer can still be trimmed off the initial
        // frame; afterwards it can only shrink, never grow.
        let previousFooter = strips.isEmpty ? matchingRows : footerHeight
        let newFooter = min(previousFooter, matchingRows)
        let bodyHeightBefore = strips.isEmpty ? frameHeight - previousFooter : initialBodyHeight

        let shift = min(verticalShift, frameHeight - previousFooter - 1)
        guard shift >= 4 else {
            return false
        }

        // The body of the last frame ended at row `frameHeight - previousFooter`;
        // in this frame that content sits `shift` rows higher. New content runs
        // from there down to the top of this frame's footer.
        let stripTop = frameHeight - previousFooter - shift
        let fullStripHeight = shift + previousFooter - newFooter
        let headroom = maxHeight - (bodyHeightBefore + appendedHeight + newFooter)
        // Clamping keeps the rows adjacent to the seam, not the bottom rows.
        let stripHeight = min(fullStripHeight, headroom)
        guard stripHeight >= 4 else {
            return false
        }

        let stripRect = CGRect(x: 0, y: stripTop, width: frame.width, height: stripHeight)

        // Copy the strip into its own backing store; a bare cropping(to:)
        // would keep the entire source frame alive for the session.
        guard let strip = copyStrip(from: frame, rect: stripRect) else {
            return false
        }
        var newFooterImage: CGImage?
        if newFooter > 0 {
            let footerRect = CGRect(x: 0, y: frameHeight - newFooter, width: frame.width, height: newFooter)
            guard let footerStrip = copyStrip(from: frame, rect: footerRect) else {
                return false
            }
            newFooterImage = footerStrip
        }

        initialBodyHeight = bodyHeightBefore
        strips.append(strip)
        appendedHeight += strip.height
        footerHeight = newFooter
        footer = newFooterImage
        lastBottomBand = currentBand
        return true
    }

    private static func footerSearchRows(height: Int, ratio: Double) -> Int {
        max(0, min(height - 1, Int(Double(height) * ratio)))
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

    /// Composites the initial frame body, all appended strips, and the
    /// footer top-to-bottom. Positions are computed in native CG space
    /// (bottom-left origin) with no flip transform, so every segment renders
    /// upright.
    private func makeImage() -> CGImage? {
        guard hasAppendedContent else { return initialImage }

        let initialBody: CGImage
        if initialBodyHeight == initialImage.height {
            initialBody = initialImage
        } else {
            guard let cropped = initialImage.cropping(
                to: CGRect(x: 0, y: 0, width: initialImage.width, height: initialBodyHeight)
            ) else {
                return nil
            }
            initialBody = cropped
        }

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

        context.interpolationQuality = .none

        var segmentTop = totalHeight
        for segment in [initialBody] + strips + (footer.map { [$0] } ?? []) {
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

/// The bottom rows of a frame rendered into a known RGBA8 layout, so rows
/// can be compared byte-for-byte between frames.
private struct BottomRowBand {
    let rows: Int
    let bytesPerRow: Int
    /// Row 0 is the topmost row of the band; the last row is the frame's bottom row.
    let bytes: [UInt8]

    init?(image: CGImage, rows: Int) {
        guard rows > 0, rows <= image.height,
              let cropped = image.cropping(
                to: CGRect(x: 0, y: image.height - rows, width: image.width, height: rows)
              ) else {
            return nil
        }
        let bytesPerRow = image.width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * rows)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: image.width,
                height: rows,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.interpolationQuality = .none
            context.draw(cropped, in: CGRect(x: 0, y: 0, width: image.width, height: rows))
            return true
        }
        guard drawn else { return nil }
        self.rows = rows
        self.bytesPerRow = bytesPerRow
        self.bytes = bytes
    }

    /// Number of consecutive rows, counted up from the bottom, that are
    /// byte-identical in both bands.
    func matchingBottomRows(with other: BottomRowBand) -> Int {
        guard rows == other.rows, bytesPerRow == other.bytesPerRow else { return 0 }
        var matched = 0
        bytes.withUnsafeBufferPointer { mine in
            other.bytes.withUnsafeBufferPointer { theirs in
                for row in stride(from: rows - 1, through: 0, by: -1) {
                    let start = row * bytesPerRow
                    guard memcmp(mine.baseAddress! + start, theirs.baseAddress! + start, bytesPerRow) == 0 else {
                        return
                    }
                    matched += 1
                }
            }
        }
        return matched
    }
}
