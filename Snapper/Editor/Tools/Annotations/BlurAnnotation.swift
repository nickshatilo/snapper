import AppKit
import CoreImage

final class BlurAnnotation: Annotation {
    private static let ciContext = CIContext(options: [.cacheIntermediates: true])

    let id: UUID
    let type: ToolType = .blur
    var zOrder: Int = 0
    var isVisible: Bool = true

    let rect: CGRect
    let intensity: CGFloat
    let sourceImage: CGImage
    private var cachedRegionImage: CGImage?

    var boundingRect: CGRect { rect }

    init(id: UUID = UUID(), rect: CGRect, intensity: CGFloat, sourceImage: CGImage) {
        self.id = id
        self.rect = rect
        self.intensity = intensity
        self.sourceImage = sourceImage
    }

    func render(in context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }

        let normalizedRect = rect.standardized.integral
        guard normalizedRect.width > 1, normalizedRect.height > 1 else { return }

        if cachedRegionImage == nil {
            cachedRegionImage = makeBlurredRegion(rect: normalizedRect)
        }
        guard let blurredRegion = cachedRegionImage else { return }

        context.draw(blurredRegion, in: normalizedRect)
    }

    func duplicate() -> any Annotation {
        let copy = BlurAnnotation(
            id: id,
            rect: rect,
            intensity: intensity,
            sourceImage: sourceImage
        )
        copy.zOrder = zOrder
        copy.isVisible = isVisible
        return copy
    }

    private func makeBlurredRegion(rect: CGRect) -> CGImage? {
        let width = max(1, Int(rect.width.rounded()))
        let height = max(1, Int(rect.height.rounded()))

        guard let regionContext = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: sourceImage.bitsPerComponent,
            bytesPerRow: 0,
            space: sourceImage.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Draw source image shifted into local region coordinates.
        regionContext.translateBy(x: -rect.minX, y: -rect.minY)
        regionContext.draw(
            sourceImage,
            in: CGRect(
                x: 0,
                y: 0,
                width: sourceImage.width,
                height: sourceImage.height
            )
        )

        guard let regionImage = regionContext.makeImage() else { return nil }

        let ciInput = CIImage(cgImage: regionImage)
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        filter.setValue(ciInput, forKey: kCIInputImageKey)
        filter.setValue(max(0.5, intensity), forKey: kCIInputRadiusKey)

        guard let output = filter.outputImage?.cropped(to: ciInput.extent) else { return nil }
        return Self.ciContext.createCGImage(output, from: ciInput.extent)
    }
}
