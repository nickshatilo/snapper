import AppKit
import CoreImage

final class PixelateAnnotation: Annotation {
    let id = UUID()
    let type: ToolType = .pixelate
    var zOrder: Int = 0
    var isVisible: Bool = true

    let rect: CGRect
    let blockSize: CGFloat

    var boundingRect: CGRect { rect }

    init(rect: CGRect, blockSize: CGFloat) {
        self.rect = rect
        self.blockSize = blockSize
    }

    func render(in context: CGContext) {
        context.saveGState()

        guard let currentImage = context.makeImage(),
              let cropped = currentImage.cropping(to: rect) else {
            context.restoreGState()
            return
        }

        let ciImage = CIImage(cgImage: cropped)
        let filter = CIFilter(name: "CIPixellate")!
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(blockSize, forKey: kCIInputScaleKey)
        filter.setValue(CIVector(x: rect.midX, y: rect.midY), forKey: kCIInputCenterKey)

        let ciContext = CIContext()
        if let output = filter.outputImage,
           let pixelated = ciContext.createCGImage(output, from: ciImage.extent) {
            context.draw(pixelated, in: rect)
        }

        context.restoreGState()
    }
}
