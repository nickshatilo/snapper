import AppKit

@Observable
final class CanvasState {
    struct Snapshot {
        let baseImage: CGImage
        let annotations: [any Annotation]
        let selectedAnnotationID: UUID?
        let selectedAnnotationIDs: Set<UUID>
    }

    var baseImage: CGImage
    var annotations: [any Annotation] = []
    var isOCRProcessing: Bool
    var recognizedTextRegionCount: Int = 0
    var zoomLevel: CGFloat = 1.0
    var panOffset: CGPoint = .zero
    var selectedAnnotationID: UUID?
    var selectedAnnotationIDs: Set<UUID> = []
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
            selectedAnnotationIDs.remove(id)
            if selectedAnnotationID == id {
                selectedAnnotationID = selectedAnnotationIDs.first
            }
            undoManager.recordRemove(annotation: annotation, state: self)
        }
    }

    func selectedAnnotation() -> (any Annotation)? {
        guard let selectedAnnotationID else { return nil }
        return annotations.first(where: { $0.id == selectedAnnotationID })
    }

    func selectedAnnotations() -> [any Annotation] {
        let ids = effectiveSelectedAnnotationIDs()
        guard !ids.isEmpty else { return [] }
        return annotations.filter { ids.contains($0.id) }
    }

    func replaceAnnotation(_ updatedAnnotation: any Annotation, recordUndo: Bool = true) {
        guard let index = annotations.firstIndex(where: { $0.id == updatedAnnotation.id }) else { return }

        let previous = annotations[index].duplicate()
        annotations[index] = updatedAnnotation
        selectedAnnotationID = updatedAnnotation.id
        selectedAnnotationIDs.insert(updatedAnnotation.id)

        if recordUndo {
            undoManager.recordModify(
                oldAnnotation: previous,
                newAnnotation: updatedAnnotation.duplicate(),
                state: self
            )
        }
    }

    @discardableResult
    func bringAnnotationToFront(id: UUID, recordUndo: Bool = true) -> Bool {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return false }

        if index == annotations.count - 1 {
            selectedAnnotationID = id
            selectedAnnotationIDs = [id]
            return true
        }

        let oldSnapshot = recordUndo ? makeSnapshot() : nil

        let annotation = annotations.remove(at: index)
        let maxZOrder = annotations.map(\.zOrder).max() ?? 0
        annotation.zOrder = max(maxZOrder + 1, annotation.zOrder + 1)
        annotations.append(annotation)
        selectedAnnotationID = id
        selectedAnnotationIDs = [id]

        if recordUndo, let oldSnapshot {
            let newSnapshot = makeSnapshot()
            undoManager.recordSnapshot(oldState: oldSnapshot, newState: newSnapshot, state: self)
        }

        return true
    }

    func makeSnapshot() -> Snapshot {
        Snapshot(
            baseImage: baseImage,
            annotations: annotations.map { $0.duplicate() },
            selectedAnnotationID: selectedAnnotationID,
            selectedAnnotationIDs: selectedAnnotationIDs
        )
    }

    func restore(from snapshot: Snapshot) {
        baseImage = snapshot.baseImage
        annotations = snapshot.annotations.map { $0.duplicate() }
        selectedAnnotationID = snapshot.selectedAnnotationID
        selectedAnnotationIDs = snapshot.selectedAnnotationIDs
    }

    @discardableResult
    func applyActiveCrop() -> Bool {
        let oldSnapshot = makeSnapshot()
        let imageBounds = CGRect(x: 0, y: 0, width: baseImage.width, height: baseImage.height)
        guard let cropRect = annotations
            .compactMap({ $0 as? CropAnnotation })
            .last?
            .rect
            .standardized
            .intersection(imageBounds),
            cropRect.width > 1,
            cropRect.height > 1 else {
            return false
        }

        let outputWidth = max(1, Int(cropRect.width.rounded()))
        let outputHeight = max(1, Int(cropRect.height.rounded()))

        guard let context = CGContext(
            data: nil,
            width: outputWidth,
            height: outputHeight,
            bitsPerComponent: baseImage.bitsPerComponent,
            bytesPerRow: 0,
            space: baseImage.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }

        context.saveGState()
        context.translateBy(x: -cropRect.minX, y: -cropRect.minY)
        context.draw(baseImage, in: imageBounds)
        context.restoreGState()

        guard let croppedBaseImage = context.makeImage() else { return false }

        let translation = CGPoint(x: -cropRect.minX, y: -cropRect.minY)
        var translatedAnnotations: [any Annotation] = []

        for annotation in annotations where !(annotation is CropAnnotation) {
            guard let translated = AnnotationGeometry.translated(annotation, by: translation) else { continue }
            translated.zOrder = annotation.zOrder
            translated.isVisible = annotation.isVisible

            if let blur = translated as? BlurAnnotation {
                let updated = BlurAnnotation(
                    id: blur.id,
                    rect: blur.rect,
                    intensity: blur.intensity,
                    sourceImage: croppedBaseImage
                )
                updated.zOrder = blur.zOrder
                updated.isVisible = blur.isVisible
                translatedAnnotations.append(updated)
                continue
            }

            if let pixelate = translated as? PixelateAnnotation {
                let updated = PixelateAnnotation(
                    id: pixelate.id,
                    rect: pixelate.rect,
                    blockSize: pixelate.blockSize,
                    sourceImage: croppedBaseImage
                )
                updated.zOrder = pixelate.zOrder
                updated.isVisible = pixelate.isVisible
                translatedAnnotations.append(updated)
                continue
            }

            translatedAnnotations.append(translated)
        }

        baseImage = croppedBaseImage
        annotations = translatedAnnotations
        selectedAnnotationID = nil
        selectedAnnotationIDs = []
        let newSnapshot = makeSnapshot()
        undoManager.recordSnapshot(oldState: oldSnapshot, newState: newSnapshot, state: self)
        return true
    }

    private func effectiveSelectedAnnotationIDs() -> Set<UUID> {
        if selectedAnnotationIDs.isEmpty, let selectedAnnotationID {
            return [selectedAnnotationID]
        }
        return selectedAnnotationIDs
    }

    func renderFinalImage() -> CGImage? {
        let imageBounds = CGRect(x: 0, y: 0, width: baseImage.width, height: baseImage.height)
        let activeCropRect = annotations
            .compactMap { $0 as? CropAnnotation }
            .last?
            .rect
            .standardized
            .intersection(imageBounds)

        let exportRect: CGRect
        if let cropRect = activeCropRect, cropRect.width > 1, cropRect.height > 1 {
            exportRect = cropRect
        } else {
            exportRect = imageBounds
        }

        let outputWidth = max(1, Int(exportRect.width.rounded()))
        let outputHeight = max(1, Int(exportRect.height.rounded()))

        guard let context = CGContext(
            data: nil,
            width: outputWidth,
            height: outputHeight,
            bitsPerComponent: baseImage.bitsPerComponent,
            bytesPerRow: 0,
            space: baseImage.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Render in annotation coordinate space; when crop is active, shift origin so crop rect becomes output bounds.
        context.saveGState()
        context.translateBy(x: -exportRect.minX, y: -exportRect.minY)
        context.draw(baseImage, in: imageBounds)

        // Crop is applied as final output bounds, not rendered as overlay pixels.
        for annotation in annotations where annotation.isVisible && !(annotation is CropAnnotation) {
            annotation.render(in: context)
        }
        context.restoreGState()

        return context.makeImage()
    }
}
