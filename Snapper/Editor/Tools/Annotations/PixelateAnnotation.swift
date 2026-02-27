import AppKit
import CoreImage

final class PixelateAnnotation: Annotation {
    private final class CachedImageBox {
        let image: CGImage

        init(_ image: CGImage) {
            self.image = image
        }
    }

    private static let ciContext = CIContext(options: [.cacheIntermediates: true])
    private static let processedImageCache: NSCache<NSString, CachedImageBox> = {
        let cache = NSCache<NSString, CachedImageBox>()
        cache.countLimit = 6
        cache.totalCostLimit = 256 * 1024 * 1024
        return cache
    }()

    let id: UUID
    let type: ToolType = .pixelate
    var zOrder: Int = 0
    var isVisible: Bool = true

    let rect: CGRect
    let blockSize: CGFloat
    let sourceImage: CGImage
    private var cachedProcessedImage: CGImage?

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

        if cachedProcessedImage == nil {
            let imageBounds = CGRect(x: 0, y: 0, width: sourceImage.width, height: sourceImage.height)
            let cropRect = normalizedRect.intersection(imageBounds)
            guard cropRect.width > 1, cropRect.height > 1,
                  let croppedSource = sourceImage.cropping(to: cropRect) else { return }
            cachedProcessedImage = Self.processedCroppedImage(for: croppedSource, blockSize: blockSize, cropRect: cropRect)
        }
        guard let processedImage = cachedProcessedImage else { return }

        context.clip(to: normalizedRect)
        context.draw(processedImage, in: normalizedRect)
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

    private static func processedCroppedImage(for croppedSource: CGImage, blockSize: CGFloat, cropRect: CGRect) -> CGImage? {
        let key = cacheKey(for: croppedSource, blockSize: blockSize, cropRect: cropRect)
        if let cached = processedImageCache.object(forKey: key) {
            return cached.image
        }

        let ciInput = CIImage(cgImage: croppedSource)
        guard let filter = CIFilter(name: "CIPixellate") else { return nil }
        filter.setValue(ciInput, forKey: kCIInputImageKey)
        filter.setValue(max(1, blockSize), forKey: kCIInputScaleKey)
        filter.setValue(CIVector(x: ciInput.extent.midX, y: ciInput.extent.midY), forKey: kCIInputCenterKey)

        guard let output = filter.outputImage?.cropped(to: ciInput.extent) else { return nil }
        guard let processedImage = Self.ciContext.createCGImage(output, from: ciInput.extent) else {
            return nil
        }

        let estimatedCost = max(1, croppedSource.width * croppedSource.height * 4)
        processedImageCache.setObject(CachedImageBox(processedImage), forKey: key, cost: estimatedCost)
        return processedImage
    }

    static func clearCache() {
        processedImageCache.removeAllObjects()
    }

    private static func cacheKey(for sourceImage: CGImage, blockSize: CGFloat, cropRect: CGRect) -> NSString {
        let pointer = UInt(bitPattern: Unmanaged.passUnretained(sourceImage).toOpaque())
        let normalizedBlockSize = Int((max(1, blockSize) * 10).rounded())
        let r = cropRect
        return "\(pointer):\(sourceImage.width)x\(sourceImage.height):\(normalizedBlockSize):\(Int(r.minX)),\(Int(r.minY)),\(Int(r.width)),\(Int(r.height))" as NSString
    }
}
