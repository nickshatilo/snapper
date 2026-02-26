import AppKit

@Observable
final class CanvasState {
    let baseImage: CGImage
    var annotations: [any Annotation] = []
    var isOCRProcessing: Bool
    var recognizedTextRegionCount: Int = 0
    var zoomLevel: CGFloat = 1.0
    var panOffset: CGPoint = .zero
    var selectedAnnotationID: UUID?
    let undoManager = UndoRedoManager()

    var imageWidth: Int { baseImage.width }
    var imageHeight: Int { baseImage.height }

    init(image: CGImage) {
        self.baseImage = image
        self.isOCRProcessing = false
    }

    func addAnnotation(_ annotation: any Annotation) {
        annotations.append(annotation)
        undoManager.recordAdd(annotation: annotation, state: self)
    }

    func removeAnnotation(id: UUID) {
        if let idx = annotations.firstIndex(where: { $0.id == id }) {
            let annotation = annotations.remove(at: idx)
            undoManager.recordRemove(annotation: annotation, state: self)
        }
    }

    func renderFinalImage() -> CGImage? {
        let width = baseImage.width
        let height = baseImage.height

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: baseImage.bitsPerComponent,
            bytesPerRow: 0,
            space: baseImage.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let imageRect = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(baseImage, in: imageRect)

        // Crop is applied as final output bounds, not rendered as overlay pixels.
        for annotation in annotations where annotation.isVisible && !(annotation is CropAnnotation) {
            annotation.render(in: context)
        }

        guard let renderedImage = context.makeImage() else { return nil }

        guard let cropRect = annotations.compactMap({ $0 as? CropAnnotation }).last?.rect else {
            return renderedImage
        }

        let imageBounds = CGRect(x: 0, y: 0, width: width, height: height)
        let normalizedCropRect = cropRect.standardized.intersection(imageBounds).integral
        guard normalizedCropRect.width > 1, normalizedCropRect.height > 1 else {
            return renderedImage
        }

        return renderedImage.cropping(to: normalizedCropRect) ?? renderedImage
    }
}
