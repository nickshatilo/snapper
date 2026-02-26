import AppKit
import CoreImage

final class BlurAnnotation: Annotation {
    let id = UUID()
    let type: ToolType = .blur
    var zOrder: Int = 0
    var isVisible: Bool = true

    let rect: CGRect
    let intensity: CGFloat
    private var cachedBlur: CGImage?

    var boundingRect: CGRect { rect }

    init(rect: CGRect, intensity: CGFloat) {
        self.rect = rect
        self.intensity = intensity
    }

    func render(in context: CGContext) {
        context.saveGState()

        // Create a blurred version of the region
        guard let currentImage = context.makeImage(),
              let cropped = currentImage.cropping(to: rect) else {
            context.restoreGState()
            return
        }

        let ciImage = CIImage(cgImage: cropped)
        let filter = CIFilter(name: "CIGaussianBlur")!
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(intensity, forKey: kCIInputRadiusKey)

        let ciContext = CIContext()
        if let output = filter.outputImage,
           let blurred = ciContext.createCGImage(output, from: ciImage.extent) {
            context.draw(blurred, in: rect)
        }

        context.restoreGState()
    }
}
