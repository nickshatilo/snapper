import AppKit

final class CanvasNSView: NSView, NSTextFieldDelegate {
    var canvasState: CanvasState
    var toolManager: ToolManager

    private var trackingArea: NSTrackingArea?
    private var isDragging = false
    private var isPanning = false
    private var hasInitializedViewport = false
    private var viewportImageSize: CGSize = .zero
    private var wasTextSelectionToolActive = false
    private var wasCropToolActive = false
    private var hasCompletedTextRecognition = false
    private var textRecognitionTask: Task<Void, Never>?
    private var nextTextRecognitionRetryDate: Date = .distantPast
    private var recognizedTextBlocks: [OCRTextBlock] = []
    private var selectedTextBlockIDs: Set<UUID> = []
    private var selectedAnnotationIDs: Set<UUID> = []
    private var textSelectionStartPoint: CGPoint?
    private var textSelectionRect: CGRect?
    private var annotationMarqueeStartPoint: CGPoint?
    private var annotationMarqueeRect: CGRect?
    private var annotationMarqueeBaseSelection: Set<UUID> = []
    private var annotationMarqueeBasePrimaryID: UUID?
    private var contextMenuAnnotationID: UUID?
    private var hoverImagePoint: CGPoint?
    private var annotationEditSession: AnnotationEditSession?
    private var inlineTextEditSession: InlineTextEditSession?
    private var suppressInlineTextEndHandling = false

    private struct AnnotationEditSession {
        enum Mode {
            case move([UUID: any Annotation])
            case resize(AnnotationResizeHandle)
            case rotate(
                initialPointerAngle: CGFloat,
                originalRotationDegrees: CGFloat,
                center: CGPoint,
                anchorCorner: AnnotationResizeHandle
            )
        }

        let annotationID: UUID
        let originalAnnotation: any Annotation
        let originalFrame: CGRect
        let startPoint: CGPoint
        let mode: Mode
    }

    private struct SingleSelectionContext {
        let id: UUID
        let annotation: any Annotation
        let frame: CGRect
    }

    private struct InlineTextEditSession {
        let annotationID: UUID
        let textField: InlineTextField
    }

    private final class InlineTextField: NSTextField {
        var onSubmit: (() -> Void)?
        var onCancel: (() -> Void)?

        override func keyDown(with event: NSEvent) {
            switch event.keyCode {
            case 36, 76: // Return / Enter
                onSubmit?()
            case 53: // Escape
                onCancel?()
            default:
                super.keyDown(with: event)
            }
        }
    }

    init(canvasState: CanvasState, toolManager: ToolManager) {
        self.canvasState = canvasState
        self.toolManager = toolManager
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.masksToBounds = true
        viewportImageSize = CGSize(width: canvasState.imageWidth, height: canvasState.imageHeight)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    deinit {
        textRecognitionTask?.cancel()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        resetViewportIfImageChanged()
        configureInitialViewportIfNeeded()
        syncTextSelectionState()
        synchronizeAnnotationSelectionState()
        syncCropModeState()
        if toolManager.currentTool != .textSelect,
           toolManager.currentTool != .text,
           inlineTextEditSession != nil {
            finishInlineTextEditing(commit: true)
        }

        context.setFillColor(NSColor.controlBackgroundColor.cgColor)
        context.fill(bounds)

        context.saveGState()
        context.clip(to: bounds)
        context.translateBy(x: canvasState.panOffset.x, y: canvasState.panOffset.y)
        context.scaleBy(x: canvasState.zoomLevel, y: canvasState.zoomLevel)

        let imageRect = CGRect(x: 0, y: 0, width: canvasState.imageWidth, height: canvasState.imageHeight)
        if toolManager.currentTool == .crop, let cropRect = activeCropPreviewRect() {
            drawBaseAndAnnotations(in: context, imageRect: imageRect, clipRect: cropRect)
        } else {
            drawBaseAndAnnotations(in: context, imageRect: imageRect, clipRect: nil)
        }

        if toolManager.currentTool == .ocr {
            drawTextSelectionOverlay(in: context, imageRect: imageRect)
        }

        if toolManager.currentTool != .ocr {
            drawAnnotationSelectionOverlay(in: context)
            drawAnnotationMarqueeOverlay(in: context)
        }

        context.restoreGState()
        updateInlineTextEditorFrameAndStyle()
    }

    override func layout() {
        super.layout()
        syncTextSelectionState()
    }

    // MARK: - Coordinate Conversion

    private func imagePoint(from viewPoint: NSPoint) -> NSPoint {
        NSPoint(
            x: (viewPoint.x - canvasState.panOffset.x) / canvasState.zoomLevel,
            y: (viewPoint.y - canvasState.panOffset.y) / canvasState.zoomLevel
        )
    }

    private func clampedImagePoint(_ point: CGPoint) -> CGPoint {
        let maxX = CGFloat(canvasState.imageWidth)
        let maxY = CGFloat(canvasState.imageHeight)
        return CGPoint(
            x: min(max(point.x, 0), maxX),
            y: min(max(point.y, 0), maxY)
        )
    }

    private func imageBounds() -> CGRect {
        CGRect(x: 0, y: 0, width: canvasState.imageWidth, height: canvasState.imageHeight)
    }

    private func drawBaseAndAnnotations(
        in context: CGContext,
        imageRect: CGRect,
        clipRect: CGRect?
    ) {
        if let clipRect {
            context.saveGState()
            context.clip(to: clipRect)
        }

        context.draw(canvasState.baseImage, in: imageRect)
        for annotation in canvasState.annotations where shouldRender(annotation) {
            annotation.render(in: context)
        }

        if clipRect != nil {
            context.restoreGState()
        }
    }

    private func shouldRender(_ annotation: any Annotation) -> Bool {
        guard annotation.isVisible else { return false }
        if annotation is CropAnnotation { return false }
        if let inlineSession = inlineTextEditSession,
           inlineSession.annotationID == annotation.id {
            return false
        }
        return true
    }

    private func shouldAutoSwitchToSelectionAfterCommit(from tool: ToolType) -> Bool {
        switch tool {
        case .arrow, .rectangle, .ellipse, .line, .blur, .pixelate, .spotlight:
            return true
        default:
            return false
        }
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        hoverImagePoint = imagePoint(from: viewPoint)
        synchronizeAnnotationSelectionState()

        if let session = inlineTextEditSession,
           !session.textField.frame.contains(viewPoint) {
            finishInlineTextEditing(commit: true)
        }

        if event.modifierFlags.contains(.option) || toolManager.currentTool == .hand {
            isPanning = true
            return
        }

        if toolManager.currentTool == .crop {
            let point = imagePoint(from: viewPoint)
            let cropAnnotation = ensureActiveCropAnnotation()
            setSelectedAnnotationIDs([cropAnnotation.id], primaryID: cropAnnotation.id)
            let hitCrop: (any Annotation)? = cropAnnotation.hitTest(point: point) ? cropAnnotation : nil
            _ = beginAnnotationInteraction(at: point, hitAnnotation: hitCrop)
            needsDisplay = true
            return
        }

        if toolManager.currentTool != .textSelect && toolManager.currentTool != .ocr {
            let point = imagePoint(from: viewPoint)
            let hitAnnotation = topmostAnnotation(at: point)
            let isToggleSelecting = event.modifierFlags.contains(.shift) || event.modifierFlags.contains(.command)

            if isToggleSelecting, let hitAnnotation {
                toolManager.currentTool = .textSelect
                toggleSelection(for: hitAnnotation.id)
                clearTextSelection()
                needsDisplay = true
                return
            }

            if event.clickCount >= 2,
               let textAnnotation = hitAnnotation as? TextAnnotation {
                toolManager.currentTool = .textSelect
                setSelectedAnnotationIDs([textAnnotation.id], primaryID: textAnnotation.id)
                beginInlineTextEditing(for: textAnnotation)
                needsDisplay = true
                return
            }

            if beginAnnotationInteraction(at: point, hitAnnotation: hitAnnotation) {
                toolManager.currentTool = .textSelect
                clearTextSelection()
                needsDisplay = true
                return
            }
        }

        if toolManager.currentTool == .textSelect {
            let point = imagePoint(from: viewPoint)
            let hitAnnotation = topmostAnnotation(at: point)
            let isToggleSelecting = event.modifierFlags.contains(.shift) || event.modifierFlags.contains(.command)

            if event.clickCount >= 2,
               !isToggleSelecting,
               let textAnnotation = hitAnnotation as? TextAnnotation {
                setSelectedAnnotationIDs([textAnnotation.id], primaryID: textAnnotation.id)
                beginInlineTextEditing(for: textAnnotation)
                needsDisplay = true
                return
            }

            if isToggleSelecting, let hitAnnotation {
                toggleSelection(for: hitAnnotation.id)
                clearTextSelection()
                needsDisplay = true
                return
            }

            if let hitAnnotation {
                if selectedAnnotationIDs.isEmpty || !selectedAnnotationIDs.contains(hitAnnotation.id) {
                    setSelectedAnnotationIDs([hitAnnotation.id], primaryID: hitAnnotation.id)
                } else {
                    canvasState.selectedAnnotationID = hitAnnotation.id
                }
            }

            if beginAnnotationInteraction(at: point, hitAnnotation: hitAnnotation) {
                clearTextSelection()
                needsDisplay = true
                return
            }

            if hitAnnotation == nil {
                beginAnnotationMarqueeSelection(at: point, additive: isToggleSelecting)
                clearTextSelection()
                needsDisplay = true
                return
            }

            setSelectedAnnotationIDs([], primaryID: nil)
            needsDisplay = true
            return
        }

        if toolManager.currentTool == .ocr {
            let point = clampedImagePoint(imagePoint(from: viewPoint))
            beginTextSelection(at: point)
            needsDisplay = true
            return
        }

        isDragging = true
        let point = imagePoint(from: viewPoint)
        toolManager.mouseDown(at: point, canvasState: canvasState)

        if toolManager.currentTool == .text || toolManager.currentTool == .counter,
           let selectedID = canvasState.selectedAnnotationID {
            setSelectedAnnotationIDs([selectedID], primaryID: selectedID)
        }

        if toolManager.currentTool == .text {
            if let textAnnotation = topmostAnnotation(at: point) as? TextAnnotation {
                beginInlineTextEditing(for: textAnnotation)
            }
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        hoverImagePoint = imagePoint(from: viewPoint)

        if isPanning {
            canvasState.panOffset.x += event.deltaX
            canvasState.panOffset.y -= event.deltaY
            updateInlineTextEditorFrameAndStyle()
            needsDisplay = true
            return
        }

        if toolManager.currentTool == .textSelect {
            let point = imagePoint(from: viewPoint)
            if updateAnnotationInteractionIfNeeded(at: point) { return }

            if annotationMarqueeStartPoint != nil {
                updateAnnotationMarqueeSelection(to: point)
                needsDisplay = true
                return
            }

            return
        }

        if toolManager.currentTool == .crop {
            let point = imagePoint(from: viewPoint)
            _ = updateAnnotationInteractionIfNeeded(at: point)
            return
        }

        if toolManager.currentTool == .ocr {
            let point = clampedImagePoint(imagePoint(from: viewPoint))
            updateTextSelection(to: point)
            needsDisplay = true
            return
        }

        let point = imagePoint(from: viewPoint)
        toolManager.mouseDragged(to: point, canvasState: canvasState)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if isPanning {
            isPanning = false
            return
        }

        let viewPoint = convert(event.locationInWindow, from: nil)
        hoverImagePoint = imagePoint(from: viewPoint)

        if toolManager.currentTool == .textSelect {
            let point = imagePoint(from: viewPoint)
            if endAnnotationInteractionIfNeeded(at: point) { return }

            if annotationMarqueeStartPoint != nil {
                endAnnotationMarqueeSelection(at: point)
                needsDisplay = true
                return
            }

            needsDisplay = true
            return
        }

        if toolManager.currentTool == .crop {
            let point = imagePoint(from: viewPoint)
            _ = endAnnotationInteractionIfNeeded(at: point)
            return
        }

        if toolManager.currentTool == .ocr {
            let point = clampedImagePoint(imagePoint(from: viewPoint))
            endTextSelection(at: point)
            needsDisplay = true
            return
        }

        let committedFromTool = toolManager.currentTool
        let point = imagePoint(from: viewPoint)
        let committedAnnotationID = toolManager.mouseUp(at: point, canvasState: canvasState)
        if let committedAnnotationID {
            setSelectedAnnotationIDs([committedAnnotationID], primaryID: committedAnnotationID)
            if shouldAutoSwitchToSelectionAfterCommit(from: committedFromTool) {
                toolManager.currentTool = .textSelect
            }
        } else if let selectedID = canvasState.selectedAnnotationID {
            setSelectedAnnotationIDs([selectedID], primaryID: selectedID)
        }
        isDragging = false
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let viewPoint = convert(event.locationInWindow, from: nil)
        hoverImagePoint = imagePoint(from: viewPoint)
        guard toolManager.currentTool == .textSelect else { return }
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        hoverImagePoint = nil
        guard toolManager.currentTool == .textSelect else { return }
        needsDisplay = true
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard toolManager.currentTool != .ocr else {
            return nil
        }

        let viewPoint = convert(event.locationInWindow, from: nil)
        let point = imagePoint(from: viewPoint)
        guard let hitAnnotation = topmostAnnotation(at: point),
              !(hitAnnotation is CropAnnotation) else {
            contextMenuAnnotationID = nil
            return nil
        }

        contextMenuAnnotationID = hitAnnotation.id
        if !selectedAnnotationIDs.contains(hitAnnotation.id) {
            setSelectedAnnotationIDs([hitAnnotation.id], primaryID: hitAnnotation.id)
            needsDisplay = true
        }

        let menu = NSMenu(title: "Annotation")
        let bringToFront = NSMenuItem(
            title: "Bring to Front",
            action: #selector(bringContextMenuAnnotationToFront),
            keyEquivalent: ""
        )
        bringToFront.target = self
        if canvasState.annotations.last?.id == hitAnnotation.id {
            bringToFront.isEnabled = false
        }
        menu.addItem(bringToFront)
        return menu
    }

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) || event.hasPreciseScrollingDeltas {
            let delta = event.scrollingDeltaY * 0.01
            let viewPoint = convert(event.locationInWindow, from: nil)
            zoom(by: 1 + delta, around: viewPoint)
        } else {
            canvasState.panOffset.x += event.scrollingDeltaX
            canvasState.panOffset.y -= event.scrollingDeltaY
        }
        updateInlineTextEditorFrameAndStyle()
        needsDisplay = true
    }

    override func magnify(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        zoom(by: 1 + event.magnification, around: viewPoint)
        updateInlineTextEditorFrameAndStyle()
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            if discardAreaSelectionIfPresent() {
                needsDisplay = true
                return
            }
            super.keyDown(with: event)
            return
        }

        if toolManager.currentTool == .crop,
           (event.keyCode == 36 || event.keyCode == 76) {
            if canvasState.applyActiveCrop() {
                setSelectedAnnotationIDs([], primaryID: nil)
                annotationEditSession = nil
                toolManager.currentTool = .textSelect
                needsDisplay = true
            }
            return
        }

        if toolManager.currentTool != .ocr,
           (event.keyCode == 51 || event.keyCode == 117) {
            synchronizeAnnotationSelectionState()
            let selectedIDs = selectedAnnotationIDs.isEmpty
                ? (canvasState.selectedAnnotationID.map { Set([$0]) } ?? [])
                : selectedAnnotationIDs
            guard !selectedIDs.isEmpty else {
                super.keyDown(with: event)
                return
            }

            for selectedID in selectedIDs {
                canvasState.removeAnnotation(id: selectedID)
            }
            setSelectedAnnotationIDs([], primaryID: nil)
            annotationEditSession = nil
            needsDisplay = true
            return
        }

        guard event.modifierFlags.contains(.command),
              let characters = event.charactersIgnoringModifiers else {
            super.keyDown(with: event)
            return
        }

        let handled: Bool
        switch characters {
        case "=", "+":
            zoom(by: 1.12, around: CGPoint(x: bounds.midX, y: bounds.midY))
            handled = true
        case "-", "_":
            zoom(by: 1 / 1.12, around: CGPoint(x: bounds.midX, y: bounds.midY))
            handled = true
        case "0":
            configureViewportToFit()
            handled = true
        case "z":
            if event.modifierFlags.contains(.shift) {
                canvasState.undoManager.redo(state: canvasState)
            } else {
                canvasState.undoManager.undo(state: canvasState)
            }
            handled = true
        case "u":
            if event.modifierFlags.contains(.shift) {
                canvasState.undoManager.redo(state: canvasState)
            } else {
                canvasState.undoManager.undo(state: canvasState)
            }
            handled = true
        case "a":
            if toolManager.currentTool == .ocr {
                selectAllRecognizedText()
                handled = true
            } else {
                handled = false
            }
        case "c":
            if toolManager.currentTool == .ocr {
                handled = copySelectedTextToPasteboard()
            } else {
                handled = false
            }
        default:
            handled = false
        }

        if handled {
            needsDisplay = true
        } else {
            super.keyDown(with: event)
        }
    }

    @objc private func bringContextMenuAnnotationToFront() {
        guard let annotationID = contextMenuAnnotationID else { return }
        defer { contextMenuAnnotationID = nil }

        guard canvasState.bringAnnotationToFront(id: annotationID) else { return }
        setSelectedAnnotationIDs([annotationID], primaryID: annotationID)
        annotationEditSession = nil
        needsDisplay = true
    }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
        window?.makeFirstResponder(self)
    }

    private func resetViewportIfImageChanged() {
        let imageSize = CGSize(width: canvasState.imageWidth, height: canvasState.imageHeight)
        if imageSize != viewportImageSize {
            viewportImageSize = imageSize
            hasInitializedViewport = false
            resetTextRecognitionState(cancelTask: true)
        }
    }

    private func configureInitialViewportIfNeeded() {
        guard !hasInitializedViewport else { return }
        configureViewportToFit()
        hasInitializedViewport = true
    }

    private func configureViewportToFit() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let imageWidth = CGFloat(canvasState.imageWidth)
        let imageHeight = CGFloat(canvasState.imageHeight)
        guard imageWidth > 0, imageHeight > 0 else { return }

        let padding: CGFloat = 24
        let widthScale = max(0.1, (bounds.width - padding) / imageWidth)
        let heightScale = max(0.1, (bounds.height - padding) / imageHeight)
        let fitZoom = min(1.0, min(widthScale, heightScale))
        canvasState.zoomLevel = fitZoom

        let renderedWidth = imageWidth * fitZoom
        let renderedHeight = imageHeight * fitZoom
        canvasState.panOffset = CGPoint(
            x: (bounds.width - renderedWidth) / 2,
            y: (bounds.height - renderedHeight) / 2
        )
    }

    private func zoom(by factor: CGFloat, around viewPoint: CGPoint) {
        let oldZoom = canvasState.zoomLevel
        let newZoom = max(0.1, min(10.0, oldZoom * factor))
        guard newZoom != oldZoom else { return }

        let scale = newZoom / oldZoom
        canvasState.zoomLevel = newZoom
        canvasState.panOffset.x = viewPoint.x - (viewPoint.x - canvasState.panOffset.x) * scale
        canvasState.panOffset.y = viewPoint.y - (viewPoint.y - canvasState.panOffset.y) * scale
    }

    // MARK: - Annotation Editing

    private func beginAnnotationInteraction(
        at point: CGPoint,
        hitAnnotation: (any Annotation)? = nil
    ) -> Bool {
        synchronizeAnnotationSelectionState()
        let activeSelection = selectedAnnotationIDs

        if let singleSelection = singleSelectionContext() {
            if beginRotationInteractionIfNeeded(at: point, selection: singleSelection) {
                return true
            }
            if beginResizeInteractionIfNeeded(at: point, selection: singleSelection) {
                return true
            }
        }

        guard let hitAnnotation = hitAnnotation ?? topmostAnnotation(at: point) else {
            annotationEditSession = nil
            return false
        }

        let moveIDs: Set<UUID>
        if !activeSelection.isEmpty, activeSelection.contains(hitAnnotation.id) {
            moveIDs = activeSelection
        } else {
            moveIDs = [hitAnnotation.id]
            setSelectedAnnotationIDs(moveIDs, primaryID: hitAnnotation.id)
        }

        var originals: [UUID: any Annotation] = [:]
        for annotationID in moveIDs {
            if let annotation = annotation(with: annotationID) {
                originals[annotationID] = annotation.duplicate()
            }
        }

        guard !originals.isEmpty else {
            annotationEditSession = nil
            return false
        }

        let validSelection = Set(originals.keys)
        setSelectedAnnotationIDs(validSelection, primaryID: hitAnnotation.id)

        guard let primaryOriginal = originals[hitAnnotation.id] ?? originals.values.first else {
            annotationEditSession = nil
            return false
        }

        let frame = AnnotationGeometry.editableFrame(for: primaryOriginal)
        annotationEditSession = AnnotationEditSession(
            annotationID: hitAnnotation.id,
            originalAnnotation: primaryOriginal,
            originalFrame: frame,
            startPoint: point,
            mode: .move(originals)
        )

        return true
    }

    @discardableResult
    private func updateAnnotationInteractionIfNeeded(at point: CGPoint) -> Bool {
        guard annotationEditSession != nil else { return false }
        updateAnnotationInteraction(to: point)
        needsDisplay = true
        return true
    }

    @discardableResult
    private func endAnnotationInteractionIfNeeded(at point: CGPoint) -> Bool {
        guard annotationEditSession != nil else { return false }
        updateAnnotationInteraction(to: point)
        endAnnotationInteraction()
        needsDisplay = true
        return true
    }

    private func updateAnnotationInteraction(to point: CGPoint) {
        guard let session = annotationEditSession else { return }

        switch session.mode {
        case .move(let originals):
            let delta = CGPoint(x: point.x - session.startPoint.x, y: point.y - session.startPoint.y)
            for original in originals.values {
                let transformed = AnnotationGeometry.translated(original, by: delta)
                applyTransformedAnnotation(transformed, preserving: original)
            }
        case .resize(let handle):
            let resizedRect = AnnotationGeometry.rectForResize(
                handle: handle,
                originalFrame: session.originalFrame,
                currentPoint: point
            )
            let transformed = AnnotationGeometry.resized(
                session.originalAnnotation,
                from: session.originalFrame,
                to: resizedRect
            )
            applyTransformedAnnotation(transformed, preserving: session.originalAnnotation)
        case .rotate(let initialPointerAngle, let originalRotationDegrees, let center, _):
            let currentPointerAngle = atan2(point.y - center.y, point.x - center.x)
            let deltaAngle = currentPointerAngle - initialPointerAngle
            let updatedRotation = originalRotationDegrees + (deltaAngle * 180 / .pi)
            let transformed = AnnotationGeometry.rotated(session.originalAnnotation, to: updatedRotation)
            applyTransformedAnnotation(transformed, preserving: session.originalAnnotation)
        }
    }

    private func endAnnotationInteraction() {
        guard let session = annotationEditSession else { return }
        defer { annotationEditSession = nil }

        switch session.mode {
        case .move(let originals):
            for (annotationID, originalAnnotation) in originals {
                guard let finalAnnotation = annotation(with: annotationID) else { continue }
                recordModifyIfGeometryChanged(from: originalAnnotation, to: finalAnnotation)
            }

        case .resize, .rotate:
            guard let finalAnnotation = annotation(with: session.annotationID) else { return }
            recordModifyIfGeometryChanged(from: session.originalAnnotation, to: finalAnnotation)
        }
    }

    private func singleSelectionContext() -> SingleSelectionContext? {
        guard selectedAnnotationIDs.count == 1 else { return nil }
        guard let selectedID = canvasState.selectedAnnotationID ?? selectedAnnotationIDs.first,
              let selectedAnnotation = annotation(with: selectedID) else {
            return nil
        }
        return SingleSelectionContext(
            id: selectedID,
            annotation: selectedAnnotation,
            frame: AnnotationGeometry.editableFrame(for: selectedAnnotation).standardized
        )
    }

    private func beginRotationInteractionIfNeeded(
        at point: CGPoint,
        selection: SingleSelectionContext
    ) -> Bool {
        guard AnnotationGeometry.supportsRotation(selection.annotation),
              let anchorCorner = rotationHandleCorner(at: point, for: selection.frame) else {
            return false
        }

        let center = CGPoint(x: selection.frame.midX, y: selection.frame.midY)
        annotationEditSession = AnnotationEditSession(
            annotationID: selection.id,
            originalAnnotation: selection.annotation.duplicate(),
            originalFrame: selection.frame,
            startPoint: point,
            mode: .rotate(
                initialPointerAngle: atan2(point.y - center.y, point.x - center.x),
                originalRotationDegrees: AnnotationGeometry.rotationDegrees(for: selection.annotation),
                center: center,
                anchorCorner: anchorCorner
            )
        )
        return true
    }

    private func beginResizeInteractionIfNeeded(
        at point: CGPoint,
        selection: SingleSelectionContext
    ) -> Bool {
        guard AnnotationGeometry.supportsResize(selection.annotation),
              let handle = resizeHandle(at: point, for: selection.frame) else {
            return false
        }

        annotationEditSession = AnnotationEditSession(
            annotationID: selection.id,
            originalAnnotation: selection.annotation.duplicate(),
            originalFrame: selection.frame,
            startPoint: point,
            mode: .resize(handle)
        )
        return true
    }

    private func applyTransformedAnnotation(
        _ transformed: (any Annotation)?,
        preserving original: any Annotation
    ) {
        guard let transformed else { return }
        transformed.zOrder = original.zOrder
        transformed.isVisible = original.isVisible
        replaceAnnotation(transformed)
    }

    private func recordModifyIfGeometryChanged(from oldAnnotation: any Annotation, to newAnnotation: any Annotation) {
        let oldSignature = annotationGeometrySignature(oldAnnotation)
        let newSignature = annotationGeometrySignature(newAnnotation)
        guard oldSignature != newSignature else { return }

        canvasState.undoManager.recordModify(
            oldAnnotation: oldAnnotation,
            newAnnotation: newAnnotation.duplicate(),
            state: canvasState
        )
    }

    private func topmostAnnotation(at point: CGPoint) -> (any Annotation)? {
        for annotation in canvasState.annotations.reversed() where annotation.isVisible {
            if annotation.hitTest(point: point) {
                return annotation
            }
        }
        return nil
    }

    private func synchronizeAnnotationSelectionState() {
        let validIDs = Set(canvasState.annotations.map(\.id))
        selectedAnnotationIDs = Set(selectedAnnotationIDs.filter { validIDs.contains($0) })

        if let primaryID = canvasState.selectedAnnotationID {
            if validIDs.contains(primaryID) {
                if selectedAnnotationIDs.isEmpty {
                    selectedAnnotationIDs = [primaryID]
                } else if !selectedAnnotationIDs.contains(primaryID) {
                    selectedAnnotationIDs.insert(primaryID)
                }
            } else {
                canvasState.selectedAnnotationID = nil
            }
        } else if !selectedAnnotationIDs.isEmpty {
            canvasState.selectedAnnotationID = selectedAnnotationIDs.first
        }

        if selectedAnnotationIDs.isEmpty {
            canvasState.selectedAnnotationID = nil
        }
    }

    private func setSelectedAnnotationIDs(_ ids: Set<UUID>, primaryID: UUID?) {
        selectedAnnotationIDs = ids
        if let primaryID, ids.contains(primaryID) {
            canvasState.selectedAnnotationID = primaryID
        } else {
            canvasState.selectedAnnotationID = ids.first
        }
    }

    private func toggleSelection(for annotationID: UUID) {
        if selectedAnnotationIDs.contains(annotationID) {
            selectedAnnotationIDs.remove(annotationID)
            if canvasState.selectedAnnotationID == annotationID {
                canvasState.selectedAnnotationID = selectedAnnotationIDs.first
            }
        } else {
            selectedAnnotationIDs.insert(annotationID)
            canvasState.selectedAnnotationID = annotationID
        }

        if selectedAnnotationIDs.isEmpty {
            canvasState.selectedAnnotationID = nil
        }
    }

    private func beginAnnotationMarqueeSelection(at point: CGPoint, additive: Bool) {
        let start = clampedImagePoint(point)
        annotationMarqueeStartPoint = start
        annotationMarqueeRect = CGRect(origin: start, size: .zero)
        annotationMarqueeBaseSelection = additive ? selectedAnnotationIDs : []
        annotationMarqueeBasePrimaryID = additive ? canvasState.selectedAnnotationID : nil
    }

    private func updateAnnotationMarqueeSelection(to point: CGPoint) {
        guard let start = annotationMarqueeStartPoint else { return }
        let current = clampedImagePoint(point)
        let rect = CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        ).intersection(imageBounds())
        annotationMarqueeRect = rect

        let dragThreshold = max(2, 6 / max(canvasState.zoomLevel, 0.1))
        guard rect.width > dragThreshold || rect.height > dragThreshold else { return }

        var ids = annotationMarqueeBaseSelection
        ids.formUnion(intersectingAnnotationIDs(in: rect))
        let primary = resolvedPrimarySelectionID(for: ids, preferred: annotationMarqueeBasePrimaryID)
        setSelectedAnnotationIDs(ids, primaryID: primary)
    }

    private func endAnnotationMarqueeSelection(at point: CGPoint) {
        guard annotationMarqueeStartPoint != nil else { return }
        defer { clearAnnotationMarqueeSelection() }

        let rect = annotationMarqueeRect?.intersection(imageBounds()) ?? .zero
        let dragThreshold = max(2, 6 / max(canvasState.zoomLevel, 0.1))

        if rect.width <= dragThreshold && rect.height <= dragThreshold {
            if annotationMarqueeBaseSelection.isEmpty {
                setSelectedAnnotationIDs([], primaryID: nil)
            } else {
                let primary = resolvedPrimarySelectionID(
                    for: annotationMarqueeBaseSelection,
                    preferred: annotationMarqueeBasePrimaryID
                )
                setSelectedAnnotationIDs(annotationMarqueeBaseSelection, primaryID: primary)
            }
            return
        }

        var ids = annotationMarqueeBaseSelection
        ids.formUnion(intersectingAnnotationIDs(in: rect))
        let primary = resolvedPrimarySelectionID(for: ids, preferred: annotationMarqueeBasePrimaryID)
        setSelectedAnnotationIDs(ids, primaryID: primary)
    }

    private func clearAnnotationMarqueeSelection() {
        annotationMarqueeStartPoint = nil
        annotationMarqueeRect = nil
        annotationMarqueeBaseSelection = []
        annotationMarqueeBasePrimaryID = nil
    }

    private func intersectingAnnotationIDs(in rect: CGRect) -> Set<UUID> {
        let normalizedRect = rect.standardized
        guard normalizedRect.width > 0 || normalizedRect.height > 0 else { return [] }
        var ids: Set<UUID> = []
        for annotation in canvasState.annotations where annotation.isVisible {
            let frame = AnnotationGeometry.editableFrame(for: annotation).standardized
            if frame.intersects(normalizedRect) {
                ids.insert(annotation.id)
            }
        }
        return ids
    }

    private func resolvedPrimarySelectionID(for ids: Set<UUID>, preferred: UUID?) -> UUID? {
        if let preferred, ids.contains(preferred) {
            return preferred
        }
        return ids.first
    }

    private func beginInlineTextEditing(for annotation: TextAnnotation) {
        finishInlineTextEditing(commit: true)
        setSelectedAnnotationIDs([annotation.id], primaryID: annotation.id)

        let textField = InlineTextField(frame: inlineEditorFrame(for: annotation))
        textField.stringValue = annotation.text
        textField.delegate = self
        textField.font = displayFont(for: annotation)
        textField.textColor = annotation.color
        textField.drawsBackground = false
        textField.backgroundColor = .clear
        textField.isBordered = false
        textField.isBezeled = false
        textField.focusRingType = .none
        textField.lineBreakMode = .byClipping
        textField.maximumNumberOfLines = 1
        textField.usesSingleLineMode = true
        textField.onSubmit = { [weak self] in
            self?.finishInlineTextEditing(commit: true)
        }
        textField.onCancel = { [weak self] in
            self?.finishInlineTextEditing(commit: false)
        }

        addSubview(textField)
        inlineTextEditSession = InlineTextEditSession(annotationID: annotation.id, textField: textField)
        window?.makeFirstResponder(textField)
        DispatchQueue.main.async {
            if let editor = textField.currentEditor() as? NSTextView {
                editor.drawsBackground = false
                editor.backgroundColor = .clear
                editor.insertionPointColor = annotation.color
                editor.selectAll(nil)
            } else {
                textField.currentEditor()?.selectAll(nil)
            }
        }
        needsDisplay = true
    }

    private func finishInlineTextEditing(commit: Bool) {
        guard let session = inlineTextEditSession else { return }
        inlineTextEditSession = nil

        let textField = session.textField
        let rawText = textField.stringValue
        let normalizedText = rawText.trimmingCharacters(in: .newlines)
        let hasNonWhitespaceContent = !normalizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        suppressInlineTextEndHandling = true
        if window?.firstResponder as AnyObject === textField.currentEditor() || window?.firstResponder === textField {
            window?.makeFirstResponder(self)
        }
        suppressInlineTextEndHandling = false

        textField.removeFromSuperview()

        guard commit,
              let existing = annotation(with: session.annotationID) as? TextAnnotation else {
            needsDisplay = true
            return
        }

        let previous = cloneTextAnnotation(existing)
        let finalText = hasNonWhitespaceContent ? normalizedText : existing.text
        guard previous.text != finalText else {
            needsDisplay = true
            return
        }

        let updated = cloneTextAnnotation(existing, text: finalText)
        replaceAnnotation(updated)
        canvasState.selectedAnnotationID = updated.id
        canvasState.undoManager.recordModify(
            oldAnnotation: previous,
            newAnnotation: updated.duplicate(),
            state: canvasState
        )
        needsDisplay = true
    }

    private func updateInlineTextEditorFrameAndStyle() {
        guard let session = inlineTextEditSession else { return }
        guard let annotation = annotation(with: session.annotationID) as? TextAnnotation else {
            finishInlineTextEditing(commit: false)
            return
        }

        session.textField.frame = inlineEditorFrame(for: annotation)
        session.textField.font = displayFont(for: annotation)
        session.textField.textColor = annotation.color
    }

    private func inlineEditorFrame(for annotation: TextAnnotation) -> CGRect {
        let zoom = max(canvasState.zoomLevel, 0.1)
        let rect = annotation.boundingRect.standardized
        let minWidth = max(26, annotation.fontSize * zoom * 1.6)
        let minHeight = max(14, annotation.fontSize * zoom + 4)
        return CGRect(
            x: canvasState.panOffset.x + rect.minX * zoom,
            y: canvasState.panOffset.y + rect.minY * zoom,
            width: max(minWidth, rect.width * zoom),
            height: max(minHeight, rect.height * zoom)
        )
    }

    private func displayFont(for annotation: TextAnnotation) -> NSFont {
        let zoom = max(canvasState.zoomLevel, 0.1)
        let pointSize = max(annotation.fontSize * zoom, 8)
        return NSFont(name: annotation.fontName, size: pointSize) ?? NSFont.systemFont(ofSize: pointSize)
    }

    private func cloneTextAnnotation(_ annotation: TextAnnotation, text: String? = nil) -> TextAnnotation {
        let copy = TextAnnotation(
            id: annotation.id,
            position: annotation.position,
            text: text ?? annotation.text,
            fontName: annotation.fontName,
            fontSize: annotation.fontSize,
            color: annotation.color,
            rotationDegrees: annotation.rotationDegrees
        )
        copy.isBold = annotation.isBold
        copy.isItalic = annotation.isItalic
        copy.hasBackground = annotation.hasBackground
        copy.zOrder = annotation.zOrder
        copy.isVisible = annotation.isVisible
        return copy
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard !suppressInlineTextEndHandling,
              let session = inlineTextEditSession,
              let field = obj.object as? NSTextField,
              field === session.textField else {
            return
        }
        finishInlineTextEditing(commit: true)
    }

    private func annotation(with id: UUID) -> (any Annotation)? {
        canvasState.annotations.first { $0.id == id }
    }

    private func replaceAnnotation(_ annotation: any Annotation) {
        guard let index = canvasState.annotations.firstIndex(where: { $0.id == annotation.id }) else {
            return
        }
        canvasState.annotations[index] = annotation
    }

    private func annotationGeometrySignature(_ annotation: any Annotation) -> String {
        if let rectangle = annotation as? RectangleAnnotation {
            return "rectangle:\(rectangle.rect.debugDescription):rot:\(rectangle.rotationDegrees)"
        }
        if let ellipse = annotation as? EllipseAnnotation {
            return "ellipse:\(ellipse.rect.debugDescription):rot:\(ellipse.rotationDegrees)"
        }
        if let line = annotation as? LineAnnotation {
            return "line:\(line.start.debugDescription):\(line.end.debugDescription)"
        }
        if let arrow = annotation as? ArrowAnnotation {
            return "arrow:\(arrow.start.debugDescription):\(arrow.end.debugDescription)"
        }
        if let highlighter = annotation as? HighlighterAnnotation {
            return "highlighter:\(highlighter.start.debugDescription):\(highlighter.end.debugDescription)"
        }
        if let blur = annotation as? BlurAnnotation {
            return "blur:\(blur.rect.debugDescription)"
        }
        if let pixelate = annotation as? PixelateAnnotation {
            return "pixelate:\(pixelate.rect.debugDescription)"
        }
        if let spotlight = annotation as? SpotlightAnnotation {
            return "spotlight:\(spotlight.rect.debugDescription)"
        }
        if let counter = annotation as? CounterAnnotation {
            return "counter:\(counter.position.debugDescription)"
        }
        if let crop = annotation as? CropAnnotation {
            return "crop:\(crop.rect.debugDescription)"
        }
        if let text = annotation as? TextAnnotation {
            return "text:\(text.position.debugDescription):rot:\(text.rotationDegrees)"
        }
        if let pencil = annotation as? PencilAnnotation {
            var hasher = Hasher()
            hasher.combine(pencil.points.count)
            hasher.combine(pencil.strokeWidth)
            for point in pencil.points {
                hasher.combine(point.x)
                hasher.combine(point.y)
            }
            return "pencil:\(hasher.finalize())"
        }

        return "\(annotation.id):\(annotation.boundingRect.debugDescription)"
    }

    private func resizeHandle(
        at point: CGPoint,
        for frame: CGRect
    ) -> AnnotationResizeHandle? {
        guard frame.width > 0, frame.height > 0 else { return nil }
        let hitRects = handleRects(for: frame, includeExpandedHitArea: true)
        for handle in AnnotationResizeHandle.allCases {
            if let rect = hitRects[handle], rect.contains(point) {
                return handle
            }
        }
        return nil
    }

    private func drawAnnotationMarqueeOverlay(in context: CGContext) {
        guard toolManager.currentTool == .textSelect,
              let marqueeRect = annotationMarqueeRect?.standardized,
              marqueeRect.width > 0 || marqueeRect.height > 0 else {
            return
        }

        let zoom = max(canvasState.zoomLevel, 0.1)
        let accent = NSColor.controlAccentColor
        let strokeWidth = max(1 / zoom, 0.75)

        context.saveGState()
        context.setFillColor(accent.withAlphaComponent(0.12).cgColor)
        context.fill(marqueeRect)
        context.setStrokeColor(accent.withAlphaComponent(0.95).cgColor)
        context.setLineWidth(strokeWidth)
        context.setLineDash(phase: 0, lengths: [6 / zoom, 4 / zoom])
        context.stroke(marqueeRect)
        context.restoreGState()
    }

    private func drawAnnotationSelectionOverlay(in context: CGContext) {
        synchronizeAnnotationSelectionState()
        let selectedIDs = selectedAnnotationIDs
        guard !selectedIDs.isEmpty else { return }

        if let inlineSession = inlineTextEditSession,
           selectedIDs.count == 1,
           selectedIDs.contains(inlineSession.annotationID) {
            return
        }

        let zoom = max(canvasState.zoomLevel, 0.1)
        let lineWidth = max(1 / zoom, 0.75)
        let accent = NSColor.controlAccentColor

        context.saveGState()
        context.setStrokeColor(accent.withAlphaComponent(0.95).cgColor)
        context.setLineWidth(lineWidth)
        context.setLineDash(phase: 0, lengths: [6 / zoom, 4 / zoom])
        for annotationID in selectedIDs {
            guard let selectedAnnotation = annotation(with: annotationID) else { continue }
            drawSelectionFrame(for: selectedAnnotation, in: context)
        }
        context.setLineDash(phase: 0, lengths: [])

        guard let selection = singleSelectionContext() else {
            context.restoreGState()
            return
        }

        drawResizeHandlesIfNeeded(for: selection, zoom: zoom, accent: accent, in: context)
        drawRotationHandleIfNeeded(for: selection, zoom: zoom, accent: accent, in: context)

        context.restoreGState()
    }

    private func drawSelectionFrame(for annotation: any Annotation, in context: CGContext) {
        if toolManager.currentTool == .crop, annotation is CropAnnotation {
            return
        }

        let frame = AnnotationGeometry.editableFrame(for: annotation).standardized
        guard frame.width > 0, frame.height > 0 else { return }
        context.stroke(frame)
    }

    private func drawResizeHandlesIfNeeded(
        for selection: SingleSelectionContext,
        zoom: CGFloat,
        accent: NSColor,
        in context: CGContext
    ) {
        guard AnnotationGeometry.supportsResize(selection.annotation) else { return }
        let handleRects = handleRects(for: selection.frame, includeExpandedHitArea: false)
        for handle in AnnotationResizeHandle.allCases {
            guard let handleRect = handleRects[handle] else { continue }
            context.setFillColor(NSColor.white.cgColor)
            context.fillEllipse(in: handleRect)
            context.setStrokeColor(accent.cgColor)
            context.setLineWidth(max(0.8 / zoom, 0.5))
            context.strokeEllipse(in: handleRect)
        }
    }

    private func drawRotationHandleIfNeeded(
        for selection: SingleSelectionContext,
        zoom: CGFloat,
        accent: NSColor,
        in context: CGContext
    ) {
        guard AnnotationGeometry.supportsRotation(selection.annotation),
              let rotationHandle = visibleRotationHandle(for: selection.id, frame: selection.frame) else {
            return
        }

        context.setFillColor(
            (rotationHandle.isHovering ? accent.withAlphaComponent(0.95) : accent.withAlphaComponent(0.8))
                .cgColor
        )
        context.fillEllipse(in: rotationHandle.rect)

        context.setStrokeColor(NSColor.white.withAlphaComponent(0.95).cgColor)
        context.setLineWidth(max(0.9 / zoom, 0.55))
        context.strokeEllipse(in: rotationHandle.rect)
        drawRotationHandleIcon(
            in: rotationHandle.rect,
            zoom: zoom,
            context: context,
            isHovering: rotationHandle.isHovering
        )
    }

    private var rotationHandleCorners: [AnnotationResizeHandle] {
        [.topLeft, .topRight, .bottomRight, .bottomLeft]
    }

    private func rotationHandleCorner(at point: CGPoint, for frame: CGRect) -> AnnotationResizeHandle? {
        for corner in rotationHandleCorners {
            if rotationHandleRect(for: frame, corner: corner, includeExpandedHitArea: true).contains(point) {
                return corner
            }
        }
        return nil
    }

    private func visibleRotationHandle(for annotationID: UUID, frame: CGRect) -> (rect: CGRect, isHovering: Bool)? {
        if let session = annotationEditSession,
           session.annotationID == annotationID,
           case .rotate(_, _, _, let corner) = session.mode {
            return (rotationHandleRect(for: frame, corner: corner, includeExpandedHitArea: false), true)
        }

        if let hoveredRotationCorner = hoveredRotationHandleCorner(for: frame) {
            return (
                rotationHandleRect(for: frame, corner: hoveredRotationCorner, includeExpandedHitArea: false),
                true
            )
        }

        if let hoveredCorner = hoveredResizeCorner(for: frame) {
            return (
                rotationHandleRect(for: frame, corner: hoveredCorner, includeExpandedHitArea: false),
                false
            )
        }

        return nil
    }

    private func rotationHandleRect(
        for frame: CGRect,
        corner: AnnotationResizeHandle,
        includeExpandedHitArea: Bool
    ) -> CGRect {
        let zoom = max(canvasState.zoomLevel, 0.1)
        let visualSize = max(10 / zoom, 5)
        let hitExpansion = includeExpandedHitArea ? max(4 / zoom, 2) : 0
        let size = visualSize + (hitExpansion * 2)
        let offset = max(10 / zoom, 6)

        guard let cornerMeta = cornerAnchorAndDirection(for: frame, corner: corner) else {
            return .null
        }

        let center = CGPoint(
            x: cornerMeta.anchor.x + (offset * cornerMeta.direction.x),
            y: cornerMeta.anchor.y + (offset * cornerMeta.direction.y)
        )

        return CGRect(
            x: center.x - size / 2,
            y: center.y - size / 2,
            width: size,
            height: size
        )
    }

    private func drawRotationHandleIcon(
        in rect: CGRect,
        zoom: CGFloat,
        context: CGContext,
        isHovering: Bool
    ) {
        let radius = max(min(rect.width, rect.height) * 0.26, 2.2 / max(zoom, 0.1))
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let startAngle = CGFloat.pi * 0.2
        let endAngle = CGFloat.pi * 1.5
        let headLength = max(radius * 0.52, 1.8 / max(zoom, 0.1))
        let headAngle = CGFloat.pi / 5
        let tangentAngle = endAngle + (.pi / 2)
        let tip = CGPoint(
            x: center.x + cos(endAngle) * radius,
            y: center.y + sin(endAngle) * radius
        )
        let left = CGPoint(
            x: tip.x - cos(tangentAngle - headAngle) * headLength,
            y: tip.y - sin(tangentAngle - headAngle) * headLength
        )
        let right = CGPoint(
            x: tip.x - cos(tangentAngle + headAngle) * headLength,
            y: tip.y - sin(tangentAngle + headAngle) * headLength
        )

        context.saveGState()
        context.setStrokeColor(
            NSColor.white.withAlphaComponent(isHovering ? 1.0 : 0.9).cgColor
        )
        context.setLineWidth(max(0.85 / max(zoom, 0.1), 0.5))
        context.setLineCap(.round)
        context.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        context.strokePath()

        context.move(to: tip)
        context.addLine(to: left)
        context.move(to: tip)
        context.addLine(to: right)
        context.strokePath()
        context.restoreGState()
    }

    private func hoveredResizeCorner(for frame: CGRect) -> AnnotationResizeHandle? {
        guard let point = currentMouseImagePoint() else { return nil }
        let zoom = max(canvasState.zoomLevel, 0.1)
        let hoverSize = max(28 / zoom, 14)
        for corner in rotationHandleCorners {
            if cornerHoverRect(for: frame, corner: corner, size: hoverSize).contains(point) {
                return corner
            }
        }
        return nil
    }

    private func hoveredRotationHandleCorner(for frame: CGRect) -> AnnotationResizeHandle? {
        guard let point = currentMouseImagePoint() else { return nil }
        for corner in rotationHandleCorners {
            if rotationHandleRect(for: frame, corner: corner, includeExpandedHitArea: true).contains(point) {
                return corner
            }
        }
        return nil
    }

    private func currentMouseImagePoint() -> CGPoint? {
        if let hoverImagePoint {
            return hoverImagePoint
        }
        guard let window else { return nil }
        let viewPoint = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        guard bounds.contains(viewPoint) else { return nil }
        return imagePoint(from: viewPoint)
    }

    private func cornerAnchorAndDirection(
        for frame: CGRect,
        corner: AnnotationResizeHandle
    ) -> (anchor: CGPoint, direction: CGPoint)? {
        switch corner {
        case .topLeft:
            return (CGPoint(x: frame.minX, y: frame.maxY), CGPoint(x: -1, y: 1))
        case .topRight:
            return (CGPoint(x: frame.maxX, y: frame.maxY), CGPoint(x: 1, y: 1))
        case .bottomRight:
            return (CGPoint(x: frame.maxX, y: frame.minY), CGPoint(x: 1, y: -1))
        case .bottomLeft:
            return (CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: -1, y: -1))
        default:
            return nil
        }
    }

    private func cornerHoverRect(
        for frame: CGRect,
        corner: AnnotationResizeHandle,
        size: CGFloat
    ) -> CGRect {
        guard let meta = cornerAnchorAndDirection(for: frame, corner: corner) else {
            return .null
        }
        return CGRect(
            x: meta.anchor.x - size / 2,
            y: meta.anchor.y - size / 2,
            width: size,
            height: size
        )
    }

    private func handleRects(
        for frame: CGRect,
        includeExpandedHitArea: Bool
    ) -> [AnnotationResizeHandle: CGRect] {
        let zoom = max(canvasState.zoomLevel, 0.1)
        let visualSize = max(7 / zoom, 4)
        let hitExpansion = includeExpandedHitArea ? max(3 / zoom, 2) : 0
        let size = visualSize + (hitExpansion * 2)

        let centers: [AnnotationResizeHandle: CGPoint] = [
            .topLeft: CGPoint(x: frame.minX, y: frame.maxY),
            .top: CGPoint(x: frame.midX, y: frame.maxY),
            .topRight: CGPoint(x: frame.maxX, y: frame.maxY),
            .right: CGPoint(x: frame.maxX, y: frame.midY),
            .bottomRight: CGPoint(x: frame.maxX, y: frame.minY),
            .bottom: CGPoint(x: frame.midX, y: frame.minY),
            .bottomLeft: CGPoint(x: frame.minX, y: frame.minY),
            .left: CGPoint(x: frame.minX, y: frame.midY),
        ]

        return centers.mapValues { center in
            CGRect(
                x: center.x - size / 2,
                y: center.y - size / 2,
                width: size,
                height: size
            )
        }
    }

    // MARK: - OCR Text Overlay

    private func syncCropModeState() {
        let isCropToolActive = toolManager.currentTool == .crop

        if wasCropToolActive != isCropToolActive {
            let wasActive = wasCropToolActive
            wasCropToolActive = isCropToolActive
            if isCropToolActive {
                let crop = ensureActiveCropAnnotation()
                setSelectedAnnotationIDs([crop.id], primaryID: crop.id)
                annotationEditSession = nil
            } else if wasActive {
                let cropIDs = Set(canvasState.annotations.compactMap { ($0 as? CropAnnotation)?.id })
                if !cropIDs.isEmpty {
                    canvasState.annotations.removeAll { annotation in
                        cropIDs.contains(annotation.id)
                    }
                    selectedAnnotationIDs.subtract(cropIDs)
                    if let selectedID = canvasState.selectedAnnotationID, cropIDs.contains(selectedID) {
                        canvasState.selectedAnnotationID = selectedAnnotationIDs.first
                    }
                }
                annotationEditSession = nil
            }
        }

        guard isCropToolActive else { return }
        let crop = ensureActiveCropAnnotation()
        if selectedAnnotationIDs.count != 1 || !selectedAnnotationIDs.contains(crop.id) {
            setSelectedAnnotationIDs([crop.id], primaryID: crop.id)
        }
    }

    @discardableResult
    private func ensureActiveCropAnnotation() -> CropAnnotation {
        let existingCrops = canvasState.annotations.compactMap { $0 as? CropAnnotation }
        let imageRect = CGRect(
            x: 0,
            y: 0,
            width: CGFloat(canvasState.imageWidth),
            height: CGFloat(canvasState.imageHeight)
        )

        if let active = existingCrops.last {
            active.isVisible = false
            let staleCropIDs = Set(existingCrops.dropLast().map(\.id))
            if !staleCropIDs.isEmpty {
                canvasState.annotations.removeAll { annotation in
                    staleCropIDs.contains(annotation.id)
                }
                selectedAnnotationIDs.subtract(staleCropIDs)
            }

            let normalized = active.rect.standardized.intersection(imageRect)
            if normalized.width > 1, normalized.height > 1 {
                return active
            }

            let refreshed = CropAnnotation(id: active.id, rect: imageRect)
            refreshed.zOrder = active.zOrder
            refreshed.isVisible = false
            replaceAnnotation(refreshed)
            return refreshed
        }

        let crop = CropAnnotation(rect: imageRect)
        crop.isVisible = false
        canvasState.annotations.append(crop)
        return crop
    }

    private func activeCropPreviewRect() -> CGRect? {
        let imageRect = CGRect(
            x: 0,
            y: 0,
            width: CGFloat(canvasState.imageWidth),
            height: CGFloat(canvasState.imageHeight)
        )
        guard let rect = canvasState.annotations
            .compactMap({ $0 as? CropAnnotation })
            .last?
            .rect
            .standardized
            .intersection(imageRect),
            rect.width > 1,
            rect.height > 1 else {
            return nil
        }
        return rect
    }

    private func syncTextSelectionState() {
        let isTextSelectionToolActive = toolManager.currentTool == .ocr

        if wasTextSelectionToolActive != isTextSelectionToolActive {
            wasTextSelectionToolActive = isTextSelectionToolActive

            if isTextSelectionToolActive {
                beginTextRecognitionIfNeeded()
            } else {
                clearTextSelection()
                annotationEditSession = nil
                canvasState.isOCRProcessing = false
                textRecognitionTask?.cancel()
                textRecognitionTask = nil
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.window?.makeFirstResponder(self)
                }
            }
        }

        guard isTextSelectionToolActive else { return }
        beginTextRecognitionIfNeeded()
    }

    private func beginTextRecognitionIfNeeded() {
        guard !hasCompletedTextRecognition, textRecognitionTask == nil else { return }
        guard Date() >= nextTextRecognitionRetryDate else { return }

        canvasState.isOCRProcessing = true
        let image = canvasState.baseImage

        textRecognitionTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            do {
                let blocks = try await TextRecognitionService.recognizeTextBlocks(in: image)
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    self.recognizedTextBlocks = blocks
                    self.selectedTextBlockIDs.removeAll()
                    self.canvasState.recognizedTextRegionCount = blocks.count
                    self.hasCompletedTextRecognition = true
                    self.nextTextRecognitionRetryDate = .distantPast
                    self.canvasState.isOCRProcessing = false
                    self.textRecognitionTask = nil
                    self.needsDisplay = true
                }
            } catch {
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    self.recognizedTextBlocks = []
                    self.selectedTextBlockIDs.removeAll()
                    self.canvasState.recognizedTextRegionCount = 0
                    self.canvasState.isOCRProcessing = false
                    self.hasCompletedTextRecognition = false
                    self.nextTextRecognitionRetryDate = Date().addingTimeInterval(0.75)
                    self.textRecognitionTask = nil
                    self.needsDisplay = true
                }
                print("Text analysis failed: \(error)")
            }
        }
    }

    private func resetTextRecognitionState(cancelTask: Bool) {
        if cancelTask {
            textRecognitionTask?.cancel()
            textRecognitionTask = nil
        }

        finishInlineTextEditing(commit: false)
        hasCompletedTextRecognition = false
        nextTextRecognitionRetryDate = .distantPast
        recognizedTextBlocks = []
        selectedTextBlockIDs.removeAll()
        clearTextSelection()
        annotationEditSession = nil
        setSelectedAnnotationIDs([], primaryID: nil)
        canvasState.isOCRProcessing = false
        canvasState.recognizedTextRegionCount = 0
    }

    private func clearTextSelection() {
        textSelectionStartPoint = nil
        textSelectionRect = nil
        selectedTextBlockIDs.removeAll()
    }

    private func discardAreaSelectionIfPresent() -> Bool {
        var discarded = false

        if annotationMarqueeStartPoint != nil || annotationMarqueeRect != nil {
            clearAnnotationMarqueeSelection()
            discarded = true
        }

        if textSelectionStartPoint != nil || textSelectionRect != nil || !selectedTextBlockIDs.isEmpty {
            clearTextSelection()
            discarded = true
        }

        let cropIDs = Set(canvasState.annotations.compactMap { ($0 as? CropAnnotation)?.id })
        if !cropIDs.isEmpty {
            canvasState.annotations.removeAll { $0 is CropAnnotation }
            selectedAnnotationIDs.subtract(cropIDs)
            if let selectedID = canvasState.selectedAnnotationID, cropIDs.contains(selectedID) {
                canvasState.selectedAnnotationID = selectedAnnotationIDs.first
            }
            if selectedAnnotationIDs.isEmpty {
                canvasState.selectedAnnotationID = nil
            }
            annotationEditSession = nil
            discarded = true
        }

        return discarded
    }

    private func beginTextSelection(at point: CGPoint) {
        guard !recognizedTextBlocks.isEmpty, !canvasState.isOCRProcessing else { return }
        textSelectionStartPoint = point
        textSelectionRect = CGRect(origin: point, size: .zero)
        selectedTextBlockIDs.removeAll()
    }

    private func updateTextSelection(to point: CGPoint) {
        guard let start = textSelectionStartPoint else { return }
        let rect = CGRect(
            x: min(start.x, point.x),
            y: min(start.y, point.y),
            width: abs(point.x - start.x),
            height: abs(point.y - start.y)
        ).intersection(imageBounds())

        textSelectionRect = rect

        let dragThreshold = max(2, 6 / max(canvasState.zoomLevel, 0.1))
        if rect.width <= dragThreshold && rect.height <= dragThreshold {
            return
        }

        selectedTextBlockIDs = selectBlocks(in: rect)
    }

    private func endTextSelection(at point: CGPoint) {
        guard textSelectionStartPoint != nil else { return }
        defer {
            textSelectionStartPoint = nil
            textSelectionRect = nil
        }

        let rect = textSelectionRect?.intersection(imageBounds()) ?? .zero
        let dragThreshold = max(2, 6 / max(canvasState.zoomLevel, 0.1))

        if rect.width <= dragThreshold && rect.height <= dragThreshold {
            selectedTextBlockIDs = selectBlocks(near: point)
        } else {
            selectedTextBlockIDs = selectBlocks(in: rect)
        }
    }

    private func selectBlocks(in rect: CGRect) -> Set<UUID> {
        intersectingBlockIDs(in: rect)
    }

    private func intersectingBlockIDs(in rect: CGRect) -> Set<UUID> {
        let normalizedRect = rect.standardized
        guard normalizedRect.width > 0, normalizedRect.height > 0 else { return [] }

        let useCoverageThreshold = normalizedRect.width > 20 || normalizedRect.height > 20

        return Set(
            recognizedTextBlocks.compactMap { block in
                let blockRect = block.imageRect.standardized
                let intersection = blockRect.intersection(normalizedRect)
                guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else { return nil }

                if !useCoverageThreshold {
                    return block.id
                }

                let blockArea = max(blockRect.width * blockRect.height, 1)
                let coveredRatio = (intersection.width * intersection.height) / blockArea
                return coveredRatio >= 0.16 ? block.id : nil
            }
        )
    }

    private func selectBlocks(near point: CGPoint) -> Set<UUID> {
        blocksNear(point: point)
    }

    private func blocksNear(point: CGPoint) -> Set<UUID> {
        let zoom = max(canvasState.zoomLevel, 0.1)
        let hitPadding = max(8, 16 / zoom)
        let hitRect = CGRect(
            x: point.x - hitPadding,
            y: point.y - hitPadding,
            width: hitPadding * 2,
            height: hitPadding * 2
        )

        let directHits = recognizedTextBlocks.filter { $0.imageRect.intersects(hitRect) }
        if let nearestDirectHit = directHits.min(by: {
            distance(from: point, to: $0.imageRect) < distance(from: point, to: $1.imageRect)
        }) {
            return [nearestDirectHit.id]
        }

        guard let nearest = recognizedTextBlocks.min(by: {
            distance(from: point, to: $0.imageRect)
                < distance(from: point, to: $1.imageRect)
        }) else {
            return []
        }

        let nearestDistance = distance(from: point, to: nearest.imageRect)
        let maxDistance = max(14, 32 / zoom)
        return nearestDistance <= maxDistance ? [nearest.id] : []
    }

    private func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }

    private func selectAllRecognizedText() {
        guard !recognizedTextBlocks.isEmpty else { return }
        selectedTextBlockIDs = Set(recognizedTextBlocks.map(\.id))
    }

    private func copySelectedTextToPasteboard() -> Bool {
        let text = selectedText()
        guard !text.isEmpty else { return false }
        PasteboardHelper.copyText(text)
        return true
    }

    private func selectedText() -> String {
        let selectedBlocks = recognizedTextBlocks
            .filter { selectedTextBlockIDs.contains($0.id) }

        guard !selectedBlocks.isEmpty else { return "" }

        let sortedBlocks = selectedBlocks.sorted {
            let lhsRect = $0.imageRect
            let rhsRect = $1.imageRect
            let yDelta = lhsRect.midY - rhsRect.midY
            if abs(yDelta) > 6 {
                return yDelta > 0
            }
            return lhsRect.minX < rhsRect.minX
        }

        var output = ""
        var previous: OCRTextBlock?

        for block in sortedBlocks {
            if let previous {
                let previousRect = previous.imageRect
                let currentRect = block.imageRect
                let sameLine = abs(previousRect.midY - currentRect.midY) <=
                    max(5, min(previousRect.height, currentRect.height) * 0.65)
                output.append(sameLine ? " " : "\n")
            }
            output.append(block.text)
            previous = block
        }

        return output
    }

    private func drawTextSelectionOverlay(in context: CGContext, imageRect: CGRect) {
        guard !recognizedTextBlocks.isEmpty else { return }

        context.saveGState()
        context.clip(to: imageRect)

        let zoom = max(canvasState.zoomLevel, 0.1)
        let lineWidth = max(0.5, 1 / zoom)
        let hasDragRect = (textSelectionRect?.width ?? 0) > 0 && (textSelectionRect?.height ?? 0) > 0
        var previewBlockIDs: Set<UUID> = []

        if let dragRect = textSelectionRect, hasDragRect {
            previewBlockIDs = intersectingBlockIDs(in: dragRect)
        }

        let selectedRects = mergedHighlightRects(for: selectedTextBlockIDs)
        for rect in selectedRects {
            fillHighlight(
                rect,
                in: context,
                zoom: zoom,
                topAlpha: 0.08,
                bottomAlpha: 0.28
            )
        }

        let previewOnlyIDs = previewBlockIDs.subtracting(selectedTextBlockIDs)
        let previewRects = mergedHighlightRects(for: previewOnlyIDs)
        for rect in previewRects {
            fillHighlight(
                rect,
                in: context,
                zoom: zoom,
                topAlpha: 0.05,
                bottomAlpha: 0.17
            )
        }

        let accent = NSColor.controlAccentColor
        if let dragRect = textSelectionRect,
           hasDragRect {
            context.setFillColor(accent.withAlphaComponent(0.08).cgColor)
            context.fill(dragRect)

            context.setStrokeColor(accent.withAlphaComponent(0.95).cgColor)
            context.setLineWidth(lineWidth)
            context.setLineDash(phase: 0, lengths: [6 / zoom, 4 / zoom])
            context.stroke(dragRect)
            context.setLineDash(phase: 0, lengths: [])
        }

        context.restoreGState()
    }

    private func fillHighlight(
        _ rect: CGRect,
        in context: CGContext,
        zoom: CGFloat,
        topAlpha: CGFloat,
        bottomAlpha: CGFloat
    ) {
        let expanded = rect.insetBy(dx: -1 / zoom, dy: -0.5 / zoom)
        let path = CGPath(
            roundedRect: expanded,
            cornerWidth: 3 / zoom,
            cornerHeight: 3 / zoom,
            transform: nil
        )

        let color = NSColor.systemBlue
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                color.withAlphaComponent(topAlpha).cgColor,
                color.withAlphaComponent(bottomAlpha).cgColor,
            ] as CFArray,
            locations: [0, 1]
        ) else {
            context.addPath(path)
            context.setFillColor(color.withAlphaComponent(bottomAlpha).cgColor)
            context.fillPath()
            return
        }

        context.saveGState()
        context.addPath(path)
        context.clip()
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: expanded.midX, y: expanded.maxY),
            end: CGPoint(x: expanded.midX, y: expanded.minY),
            options: []
        )
        context.restoreGState()
    }

    private func mergedHighlightRects(for blockIDs: Set<UUID>) -> [CGRect] {
        guard !blockIDs.isEmpty else { return [] }

        let rects = recognizedTextBlocks
            .filter { blockIDs.contains($0.id) }
            .map(\.imageRect)
            .sorted {
                let yDelta = $0.midY - $1.midY
                if abs(yDelta) > 2 { return yDelta > 0 }
                return $0.minX < $1.minX
            }

        guard !rects.isEmpty else { return [] }

        struct LineGroup {
            var midY: CGFloat
            var rects: [CGRect]
        }

        var lines: [LineGroup] = []
        for rect in rects {
            if var last = lines.last {
                let yTolerance = max(4, min(last.rects.first?.height ?? rect.height, rect.height) * 0.7)
                if abs(last.midY - rect.midY) <= yTolerance {
                    last.rects.append(rect)
                    last.midY = (last.midY * CGFloat(last.rects.count - 1) + rect.midY) / CGFloat(last.rects.count)
                    lines[lines.count - 1] = last
                    continue
                }
            }
            lines.append(LineGroup(midY: rect.midY, rects: [rect]))
        }

        var merged: [CGRect] = []
        for line in lines {
            let sortedLineRects = line.rects.sorted { $0.minX < $1.minX }
            guard let first = sortedLineRects.first else { continue }

            var minX = first.minX
            var maxX = first.maxX
            var minY = first.minY
            var maxY = first.maxY

            for rect in sortedLineRects.dropFirst() {
                minX = min(minX, rect.minX)
                maxX = max(maxX, rect.maxX)
                minY = min(minY, rect.minY)
                maxY = max(maxY, rect.maxY)
            }

            merged.append(CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY))
        }

        return merged
    }
}
