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
    /// Installed by the canvas view so exporters can commit an in-progress
    /// inline text edit before rendering.
    @ObservationIgnored var pendingEditCommitHandler: (() -> Void)?

    var imageWidth: Int { baseImage.width }
    var imageHeight: Int { baseImage.height }

    init(image: CGImage) {
        self.baseImage = image
        self.isOCRProcessing = false
    }

    /// Commits any in-progress edit (e.g. inline text) so the model matches
    /// what the user sees. Call before exporting.
    func commitPendingEdits() {
        pendingEditCommitHandler?()
    }

    func addAnnotation(_ annotation: any Annotation) {
        annotations.append(annotation)
        undoManager.recordAdd(annotation: annotation, state: self)
    }

    func removeAnnotation(id: UUID) {
        removeAnnotations(ids: [id])
    }

    /// Removes the given annotations as a single undo step; undo restores
    /// each one at its original stacking position.
    func removeAnnotations(ids: Set<UUID>) {
        let indices = annotations.indices
            .filter { ids.contains(annotations[$0].id) }
            .sorted(by: >)
        guard !indices.isEmpty else { return }

        // Remove from the top down so each recorded index is valid at the
        // moment of removal; undo re-inserts in reverse order.
        var removals: [(annotation: any Annotation, index: Int)] = []
        for index in indices {
            removals.append((annotations.remove(at: index), index))
        }

        selectedAnnotationIDs.subtract(ids)
        if let selectedAnnotationID, ids.contains(selectedAnnotationID) {
            self.selectedAnnotationID = selectedAnnotationIDs.first
        }
        undoManager.recordRemovals(removals, state: self)
    }

    /// Replaces several annotations as one undo step. Calls sharing a
    /// `coalescingKey` in quick succession (a slider drag, a colour-panel
    /// session) collapse into a single entry.
    func replaceAnnotations(_ updatedAnnotations: [any Annotation], coalescingKey: String?) {
        var changes: [(old: any Annotation, new: any Annotation)] = []
        for updated in updatedAnnotations {
            guard let index = annotations.firstIndex(where: { $0.id == updated.id }) else { continue }
            let previous = annotations[index].duplicate()
            annotations[index] = updated
            changes.append((previous, updated.duplicate()))
        }
        undoManager.recordModifications(changes, coalescingKey: coalescingKey, state: self)
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

    /// Snapshots capture document state only. The crop rectangle is transient
    /// crop-tool UI state; keeping it in history would let undo restore an
    /// invisible crop that still clips every export.
    func makeSnapshot() -> Snapshot {
        let documentAnnotations = annotations.filter { !($0 is CropAnnotation) }
        let documentIDs = Set(documentAnnotations.map(\.id))
        let selectedID = selectedAnnotationID.flatMap { documentIDs.contains($0) ? $0 : nil }
        return Snapshot(
            baseImage: baseImage,
            annotations: documentAnnotations.map { $0.duplicate() },
            selectedAnnotationID: selectedID,
            selectedAnnotationIDs: selectedAnnotationIDs.intersection(documentIDs)
        )
    }

    func restore(from snapshot: Snapshot) {
        // Keep the live crop-tool rectangle (if any); it isn't part of history.
        var liveCrops = annotations.filter { $0 is CropAnnotation }
        if snapshot.baseImage.width != baseImage.width || snapshot.baseImage.height != baseImage.height {
            // The live crop rect is in the current image's coordinates; when
            // the image changes size, start over at the restored image's full
            // bounds, as entering the crop tool fresh would.
            let restoredBounds = CGRect(x: 0, y: 0, width: snapshot.baseImage.width, height: snapshot.baseImage.height)
            liveCrops = liveCrops.map { crop in
                let reset = CropAnnotation(id: crop.id, rect: restoredBounds)
                reset.zOrder = crop.zOrder
                reset.isVisible = crop.isVisible
                return reset
            }
        }
        baseImage = snapshot.baseImage
        annotations = snapshot.annotations.map { $0.duplicate() } + liveCrops
        selectedAnnotationID = snapshot.selectedAnnotationID
        selectedAnnotationIDs = snapshot.selectedAnnotationIDs
    }

    /// The active crop rectangle snapped to whole pixels and clamped to the
    /// image, or nil when there is no usable crop. Snapping avoids
    /// resampling (softening) the whole image on a fractional offset.
    func activeCropPixelRect() -> CGRect? {
        guard let rect = annotations.compactMap({ $0 as? CropAnnotation }).last?.rect else { return nil }
        return Self.pixelAlignedCropRect(rect, imageWidth: baseImage.width, imageHeight: baseImage.height)
    }

    static func pixelAlignedCropRect(_ rect: CGRect, imageWidth: Int, imageHeight: Int) -> CGRect? {
        let standardized = rect.standardized
        guard standardized.minX.isFinite, standardized.minY.isFinite,
              standardized.maxX.isFinite, standardized.maxY.isFinite else { return nil }
        let minX = min(max(standardized.minX.rounded(), 0), CGFloat(imageWidth))
        let minY = min(max(standardized.minY.rounded(), 0), CGFloat(imageHeight))
        let maxX = min(max(standardized.maxX.rounded(), 0), CGFloat(imageWidth))
        let maxY = min(max(standardized.maxY.rounded(), 0), CGFloat(imageHeight))
        let aligned = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        guard aligned.width > 1, aligned.height > 1 else { return nil }
        return aligned
    }

    @discardableResult
    func applyActiveCrop() -> Bool {
        let oldSnapshot = makeSnapshot()
        let imageBounds = CGRect(x: 0, y: 0, width: baseImage.width, height: baseImage.height)
        guard let cropRect = activeCropPixelRect() else {
            return false
        }

        let outputWidth = Int(cropRect.width)
        let outputHeight = Int(cropRect.height)

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
        let exportRect = activeCropPixelRect() ?? imageBounds

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
