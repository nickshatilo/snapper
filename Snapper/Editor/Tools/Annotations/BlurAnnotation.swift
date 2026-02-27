import AppKit
import CoreImage

final class BlurAnnotation: Annotation {
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
    let type: ToolType = .blur
    var zOrder: Int = 0
    var isVisible: Bool = true

    let rect: CGRect
    let intensity: CGFloat
    let sourceImage: CGImage
    private var cachedProcessedImage: CGImage?

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

        if cachedProcessedImage == nil {
            let imageBounds = CGRect(x: 0, y: 0, width: sourceImage.width, height: sourceImage.height)
            let cropRect = normalizedRect.intersection(imageBounds)
            guard cropRect.width > 1, cropRect.height > 1,
                  let croppedSource = sourceImage.cropping(to: cropRect) else { return }
            cachedProcessedImage = Self.processedCroppedImage(for: croppedSource, intensity: intensity, cropRect: cropRect)
        }
        guard let processedImage = cachedProcessedImage else { return }

        context.clip(to: normalizedRect)
        context.draw(processedImage, in: normalizedRect)
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

    private static func processedCroppedImage(for croppedSource: CGImage, intensity: CGFloat, cropRect: CGRect) -> CGImage? {
        let key = cacheKey(for: croppedSource, intensity: intensity, cropRect: cropRect)
        if let cached = processedImageCache.object(forKey: key) {
            return cached.image
        }

        let ciInput = CIImage(cgImage: croppedSource)
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        filter.setValue(ciInput, forKey: kCIInputImageKey)
        filter.setValue(max(0.5, intensity), forKey: kCIInputRadiusKey)

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

    private static func cacheKey(for sourceImage: CGImage, intensity: CGFloat, cropRect: CGRect) -> NSString {
        let pointer = UInt(bitPattern: Unmanaged.passUnretained(sourceImage).toOpaque())
        let normalizedIntensity = Int((max(0.5, intensity) * 10).rounded())
        let r = cropRect
        return "\(pointer):\(sourceImage.width)x\(sourceImage.height):\(normalizedIntensity):\(Int(r.minX)),\(Int(r.minY)),\(Int(r.width)),\(Int(r.height))" as NSString
    }
}
