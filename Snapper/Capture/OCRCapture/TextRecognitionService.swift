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
            let originalWidth = CGFloat(image.width)
            let originalHeight = CGFloat(image.height)
            let ocrImage = downscaledImageIfNeeded(image) ?? image

            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lineBlocks: [OCRTextBlock] = observations.compactMap { observation in
                    guard let topCandidate = observation.topCandidates(1).first else { return nil }
                    let text = topCandidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return nil }

                    let rect = imageRect(from: observation.boundingBox, width: originalWidth, height: originalHeight)
                    guard rect.width > 1, rect.height > 1 else { return nil }
                    return OCRTextBlock(text: text, imageRect: rect)
                }
                let detectedWordBlocks = observations.flatMap {
                    wordBlocks(
                        from: $0,
                        imageWidth: originalWidth,
                        imageHeight: originalHeight
                    )
                }
                let blocks = (detectedWordBlocks.isEmpty ? lineBlocks : detectedWordBlocks)
                    .sorted { lhs, rhs in
                        let yDelta = lhs.imageRect.midY - rhs.imageRect.midY
                        if abs(yDelta) > 6 { return yDelta > 0 }
                        return lhs.imageRect.minX < rhs.imageRect.minX
                    }

                continuation.resume(returning: Array(blocks.prefix(2000)))
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.minimumTextHeight = 0

            let handler = VNImageRequestHandler(cgImage: ocrImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    static func recognizeText(in image: CGImage) async throws -> String {
        let blocks = try await recognizeTextBlocks(in: image)
        return composeText(from: blocks)
    }

    private static func downscaledImageIfNeeded(_ image: CGImage) -> CGImage? {
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
        return context.makeImage()
    }

    private static func imageRect(from normalizedRect: CGRect, width: CGFloat, height: CGFloat) -> CGRect {
        CGRect(
            x: normalizedRect.minX * width,
            y: normalizedRect.minY * height,
            width: normalizedRect.width * width,
            height: normalizedRect.height * height
        ).integral
    }

    private static func wordBlocks(
        from observation: VNRecognizedTextObservation,
        imageWidth: CGFloat,
        imageHeight: CGFloat
    ) -> [OCRTextBlock] {
        guard let candidate = observation.topCandidates(1).first else { return [] }

        let fullText = candidate.string
        let nsRange = NSRange(location: 0, length: (fullText as NSString).length)
        var blocks: [OCRTextBlock] = []

        (fullText as NSString).enumerateSubstrings(
            in: nsRange,
            options: [.byWords, .substringNotRequired]
        ) { _, wordRange, _, _ in
            guard let swiftRange = Range(wordRange, in: fullText) else { return }
            let word = fullText[swiftRange].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !word.isEmpty else { return }
            guard let box = try? candidate.boundingBox(for: swiftRange) else { return }

            let rect = imageRect(from: box.boundingBox, width: imageWidth, height: imageHeight)
            guard rect.width > 1, rect.height > 1 else { return }
            blocks.append(OCRTextBlock(text: word, imageRect: rect))
        }

        return blocks
    }

    private static func composeText(from blocks: [OCRTextBlock]) -> String {
        guard !blocks.isEmpty else { return "" }

        let sorted = blocks.sorted {
            let yDelta = $0.imageRect.midY - $1.imageRect.midY
            if abs(yDelta) > 6 { return yDelta > 0 }
            return $0.imageRect.minX < $1.imageRect.minX
        }

        var result = ""
        var previous: OCRTextBlock?

        for block in sorted {
            if let prev = previous {
                let sameLine = abs(prev.imageRect.midY - block.imageRect.midY) <=
                    max(5, min(prev.imageRect.height, block.imageRect.height) * 0.65)
                if sameLine {
                    result.append(" ")
                } else {
                    result.append("\n")
                }
            }
            result.append(block.text)
            previous = block
        }

        return result
    }
}
