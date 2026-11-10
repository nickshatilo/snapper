import AppKit
import Vision

struct OCRTextBlock: Identifiable, Hashable {
    let id = UUID()
    let text: String
    let imageRect: CGRect
}

enum TextRecognitionService {
    static func recognizeTextBlocks(in image: CGImage) async throws -> [OCRTextBlock] {
        try await withCheckedThrowingContinuation { continuation in
            let downscaled = downscaledImageIfNeeded(image)
            let ocrImage = downscaled?.image ?? image
            let scaleToOriginal = 1.0 / (downscaled?.scale ?? 1.0)
            let ocrWidth = CGFloat(ocrImage.width)
            let ocrHeight = CGFloat(ocrImage.height)

            // On failure Vision both calls the completion handler with the error
            // and throws from `perform`; resuming twice would trap. `perform` runs
            // the handler synchronously on this thread, so a plain flag suffices.
            var didResume = false
            func resume(_ result: Result<[OCRTextBlock], Error>) {
                guard !didResume else { return }
                didResume = true
                continuation.resume(with: result)
            }

            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    resume(.failure(error))
                    return
                }

                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let recognizedBlocks = observations.flatMap {
                    blocksFromObservation(
                        from: $0,
                        ocrWidth: ocrWidth,
                        ocrHeight: ocrHeight,
                        scaleToOriginal: scaleToOriginal
                    )
                }
                let readingOrder = lines(from: recognizedBlocks).flatMap { $0 }

                resume(.success(Array(readingOrder.prefix(2000))))
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            request.minimumTextHeight = 0

            let handler = VNImageRequestHandler(cgImage: ocrImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                resume(.failure(error))
            }
            if !didResume {
                // Defensive: never leave the caller suspended forever.
                resume(.success([]))
            }
        }
    }

    static func recognizeText(in image: CGImage) async throws -> String {
        let blocks = try await recognizeTextBlocks(in: image)
        return composeText(from: blocks)
    }

    /// Ranges of the maximal runs of non-whitespace characters. Splitting on
    /// whitespace rather than word boundaries keeps punctuation attached, so
    /// "Hello," and URLs survive as written.
    static func tokenRanges(in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var tokenStart: String.Index?
        var index = text.startIndex

        while index < text.endIndex {
            if text[index].isWhitespace {
                if let start = tokenStart {
                    ranges.append(start..<index)
                    tokenStart = nil
                }
            } else if tokenStart == nil {
                tokenStart = index
            }
            index = text.index(after: index)
        }
        if let start = tokenStart {
            ranges.append(start..<text.endIndex)
        }

        return ranges
    }

    /// Groups blocks into text lines, top-to-bottom, each ordered left-to-right.
    /// Image rects are y-up, so a larger midY is higher on the page.
    static func lines(from blocks: [OCRTextBlock]) -> [[OCRTextBlock]] {
        let topToBottom = blocks.sorted { lhs, rhs in
            if lhs.imageRect.midY != rhs.imageRect.midY {
                return lhs.imageRect.midY > rhs.imageRect.midY
            }
            return lhs.imageRect.minX < rhs.imageRect.minX
        }

        var grouped: [[OCRTextBlock]] = []
        var currentLine: [OCRTextBlock] = []
        // Mean centre of the current line. Comparing against it, rather than
        // the previous block, stops a run of slightly descending blocks from
        // chaining two lines together.
        var referenceMidY: CGFloat = 0
        var minHeight: CGFloat = 0

        for block in topToBottom {
            let rect = block.imageRect
            if !currentLine.isEmpty {
                let tolerance = max(5, min(minHeight, rect.height) * 0.65)
                if abs(referenceMidY - rect.midY) <= tolerance {
                    let count = CGFloat(currentLine.count)
                    referenceMidY = (referenceMidY * count + rect.midY) / (count + 1)
                    minHeight = min(minHeight, rect.height)
                    currentLine.append(block)
                    continue
                }
                grouped.append(currentLine)
            }
            currentLine = [block]
            referenceMidY = rect.midY
            minHeight = rect.height
        }
        if !currentLine.isEmpty {
            grouped.append(currentLine)
        }

        return grouped.map { line in
            line.sorted { lhs, rhs in
                if lhs.imageRect.minX != rhs.imageRect.minX {
                    return lhs.imageRect.minX < rhs.imageRect.minX
                }
                return lhs.imageRect.midY > rhs.imageRect.midY
            }
        }
    }

    /// Blocks in reading order: words on a line separated by a space, lines by
    /// a newline.
    static func composeText(from blocks: [OCRTextBlock]) -> String {
        lines(from: blocks)
            .map { line in line.map(\.text).joined(separator: " ") }
            .joined(separator: "\n")
    }

    private static func downscaledImageIfNeeded(_ image: CGImage) -> (image: CGImage, scale: CGFloat)? {
        let maxDimension: CGFloat = 4800
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let scale = min(1.0, maxDimension / max(width, height))
        guard scale < 1.0 else { return nil }

        let targetWidth = Int(width * scale)
        let targetHeight = Int(height * scale)
        guard targetWidth > 0, targetHeight > 0 else { return nil }

        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: image.bitsPerComponent,
            bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: image.bitmapInfo.rawValue
        ) else { return nil }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        guard let result = context.makeImage() else { return nil }
        return (result, scale)
    }

    private static func imageRect(
        from normalizedRect: CGRect,
        width: CGFloat,
        height: CGFloat,
        scaleToOriginal: CGFloat = 1.0
    ) -> CGRect {
        CGRect(
            x: normalizedRect.minX * width * scaleToOriginal,
            y: normalizedRect.minY * height * scaleToOriginal,
            width: normalizedRect.width * width * scaleToOriginal,
            height: normalizedRect.height * height * scaleToOriginal
        ).integral
    }

    private static func blocksFromObservation(
        from observation: VNRecognizedTextObservation,
        ocrWidth: CGFloat,
        ocrHeight: CGFloat,
        scaleToOriginal: CGFloat
    ) -> [OCRTextBlock] {
        let tokenLevel = tokenBlocks(
            from: observation,
            imageWidth: ocrWidth,
            imageHeight: ocrHeight,
            scaleToOriginal: scaleToOriginal
        )
        if !tokenLevel.isEmpty {
            return tokenLevel
        }

        guard let lineLevel = lineBlock(
            from: observation,
            imageWidth: ocrWidth,
            imageHeight: ocrHeight,
            scaleToOriginal: scaleToOriginal
        ) else {
            return []
        }
        return [lineLevel]
    }

    private static func lineBlock(
        from observation: VNRecognizedTextObservation,
        imageWidth: CGFloat,
        imageHeight: CGFloat,
        scaleToOriginal: CGFloat
    ) -> OCRTextBlock? {
        guard let topCandidate = observation.topCandidates(1).first else { return nil }
        let text = topCandidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let rect = imageRect(
            from: observation.boundingBox,
            width: imageWidth,
            height: imageHeight,
            scaleToOriginal: scaleToOriginal
        )
        guard rect.width > 1, rect.height > 1 else { return nil }
        return OCRTextBlock(text: text, imageRect: rect)
    }

    private static func tokenBlocks(
        from observation: VNRecognizedTextObservation,
        imageWidth: CGFloat,
        imageHeight: CGFloat,
        scaleToOriginal: CGFloat
    ) -> [OCRTextBlock] {
        guard let candidate = observation.topCandidates(1).first else { return [] }

        let fullText = candidate.string
        var blocks: [OCRTextBlock] = []

        // A token without a usable box would silently drop its text; give up
        // on token-level blocks so the caller falls back to the whole line.
        for range in tokenRanges(in: fullText) {
            guard let box = try? candidate.boundingBox(for: range) else { return [] }

            let rect = imageRect(
                from: box.boundingBox,
                width: imageWidth,
                height: imageHeight,
                scaleToOriginal: scaleToOriginal
            )
            guard rect.width > 1, rect.height > 1 else { return [] }
            blocks.append(OCRTextBlock(text: String(fullText[range]), imageRect: rect))
        }

        return blocks
    }
}
