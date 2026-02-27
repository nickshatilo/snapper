import AppKit
import CoreImage

final class PixelateAnnotation: Annotation {
    private static let ciContext = CIContext(options: [.cacheIntermediates: true])

    let id: UUID
    let type: ToolType = .pixelate
    var zOrder: Int = 0
    var isVisible: Bool = true

    let rect: CGRect
    let blockSize: CGFloat
    let sourceImage: CGImage
    private var cachedRegionImage: CGImage?

    var boundingRect: CGRect { rect }

    init(id: UUID = UUID(), rect: CGRect, blockSize: CGFloat, sourceImage: CGImage) {
        self.id = id
        self.rect = rect
        self.blockSize = blockSize
        self.sourceImage = sourceImage
    }

    func render(in context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }

        let normalizedRect = rect.standardized.integral
        guard normalizedRect.width > 1, normalizedRect.height > 1 else { return }

        if cachedRegionImage == nil {
            cachedRegionImage = makePixelatedRegion(rect: normalizedRect)
        }
        guard let pixelatedRegion = cachedRegionImage else { return }

        context.draw(pixelatedRegion, in: normalizedRect)
    }

    func duplicate() -> any Annotation {
        let copy = PixelateAnnotation(
            id: id,
            rect: rect,
            blockSize: blockSize,
            sourceImage: sourceImage
        )
        copy.zOrder = zOrder
        copy.isVisible = isVisible
        return copy
    }

    private func makePixelatedRegion(rect: CGRect) -> CGImage? {
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
        guard let filter = CIFilter(name: "CIPixellate") else { return nil }
        filter.setValue(ciInput, forKey: kCIInputImageKey)
        filter.setValue(max(1, blockSize), forKey: kCIInputScaleKey)
        filter.setValue(CIVector(x: ciInput.extent.midX, y: ciInput.extent.midY), forKey: kCIInputCenterKey)

        guard let output = filter.outputImage?.cropped(to: ciInput.extent) else { return nil }
        return Self.ciContext.createCGImage(output, from: ciInput.extent)
    }
}
