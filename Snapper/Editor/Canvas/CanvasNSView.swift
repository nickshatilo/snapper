import AppKit

final class CanvasNSView: NSView {
    var canvasState: CanvasState
    var toolManager: ToolManager

    private var trackingArea: NSTrackingArea?
    private var isDragging = false
    private var isPanning = false
    private var hasInitializedViewport = false
    private var viewportImageSize: CGSize = .zero
    private var wasTextSelectionToolActive = false
    private var hasCompletedTextRecognition = false
    private var textRecognitionTask: Task<Void, Never>?
    private var nextTextRecognitionRetryDate: Date = .distantPast
    private var recognizedTextBlocks: [OCRTextBlock] = []
    private var selectedTextBlockIDs: Set<UUID> = []
    private var textSelectionStartPoint: CGPoint?
    private var textSelectionRect: CGRect?

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

        context.setFillColor(NSColor.controlBackgroundColor.cgColor)
        context.fill(bounds)

        context.saveGState()
        context.clip(to: bounds)
        context.translateBy(x: canvasState.panOffset.x, y: canvasState.panOffset.y)
        context.scaleBy(x: canvasState.zoomLevel, y: canvasState.zoomLevel)

        let imageRect = CGRect(x: 0, y: 0, width: canvasState.imageWidth, height: canvasState.imageHeight)
        context.draw(canvasState.baseImage, in: imageRect)

        for annotation in canvasState.annotations where annotation.isVisible {
            annotation.render(in: context)
        }

        if toolManager.currentTool == .textSelect {
            drawTextSelectionOverlay(in: context, imageRect: imageRect)
        }

        context.restoreGState()
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

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)

        if event.modifierFlags.contains(.option) || toolManager.currentTool == .hand {
            isPanning = true
            return
        }

        if toolManager.currentTool == .textSelect {
            let point = clampedImagePoint(imagePoint(from: viewPoint))
            beginTextSelection(at: point)
            needsDisplay = true
            return
        }

        isDragging = true
        let point = imagePoint(from: viewPoint)
        toolManager.mouseDown(at: point, canvasState: canvasState)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)

        if isPanning {
            canvasState.panOffset.x += event.deltaX
            canvasState.panOffset.y -= event.deltaY
            needsDisplay = true
            return
        }

        if toolManager.currentTool == .textSelect {
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

        if toolManager.currentTool == .textSelect {
            let point = clampedImagePoint(imagePoint(from: viewPoint))
            endTextSelection(at: point)
            needsDisplay = true
            return
        }

        let point = imagePoint(from: viewPoint)
        toolManager.mouseUp(at: point, canvasState: canvasState)
        isDragging = false
        needsDisplay = true
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
        needsDisplay = true
    }

    override func magnify(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        zoom(by: 1 + event.magnification, around: viewPoint)
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
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
            if toolManager.currentTool == .textSelect {
                selectAllRecognizedText()
                handled = true
            } else {
                handled = false
            }
        case "c":
            if toolManager.currentTool == .textSelect {
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

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
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

    // MARK: - OCR Text Overlay

    private func syncTextSelectionState() {
        let isTextSelectionToolActive = toolManager.currentTool == .textSelect

        if wasTextSelectionToolActive != isTextSelectionToolActive {
            wasTextSelectionToolActive = isTextSelectionToolActive

            if isTextSelectionToolActive {
                beginTextRecognitionIfNeeded()
            } else {
                clearTextSelection()
                canvasState.isOCRProcessing = false
                textRecognitionTask?.cancel()
                textRecognitionTask = nil
                window?.makeFirstResponder(self)
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

        hasCompletedTextRecognition = false
        nextTextRecognitionRetryDate = .distantPast
        recognizedTextBlocks = []
        selectedTextBlockIDs.removeAll()
        clearTextSelection()
        canvasState.isOCRProcessing = false
        canvasState.recognizedTextRegionCount = 0
    }

    private func clearTextSelection() {
        textSelectionStartPoint = nil
        textSelectionRect = nil
        selectedTextBlockIDs.removeAll()
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
        Set(
            recognizedTextBlocks
                .filter { $0.imageRect.intersects(rect) }
                .map(\.id)
        )
    }

    private func selectBlocks(near point: CGPoint) -> Set<UUID> {
        blocksNear(point: point)
    }

    private func blocksNear(point: CGPoint) -> Set<UUID> {
        let hitPadding = max(4, 8 / max(canvasState.zoomLevel, 0.1))
        let hitRect = CGRect(
            x: point.x - hitPadding,
            y: point.y - hitPadding,
            width: hitPadding * 2,
            height: hitPadding * 2
        )

        let directHits = recognizedTextBlocks.filter { $0.imageRect.intersects(hitRect) }
        if !directHits.isEmpty {
            return Set(directHits.map(\.id))
        }

        guard let nearest = recognizedTextBlocks.min(by: {
            distance(from: point, to: $0.imageRect)
                < distance(from: point, to: $1.imageRect)
        }) else {
            return []
        }

        let nearestDistance = distance(from: point, to: nearest.imageRect)
        return nearestDistance <= hitPadding * 2 ? [nearest.id] : []
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
            context.setFillColor(NSColor.systemBlue.withAlphaComponent(0.2).cgColor)
            let path = CGPath(
                roundedRect: rect.insetBy(dx: -1 / zoom, dy: -0.5 / zoom),
                cornerWidth: 3 / zoom,
                cornerHeight: 3 / zoom,
                transform: nil
            )
            context.addPath(path)
            context.fillPath()
        }

        let previewOnlyIDs = previewBlockIDs.subtracting(selectedTextBlockIDs)
        let previewRects = mergedHighlightRects(for: previewOnlyIDs)
        for rect in previewRects {
            context.setFillColor(NSColor.systemBlue.withAlphaComponent(0.1).cgColor)
            let path = CGPath(
                roundedRect: rect.insetBy(dx: -0.8 / zoom, dy: -0.4 / zoom),
                cornerWidth: 2.5 / zoom,
                cornerHeight: 2.5 / zoom,
                transform: nil
            )
            context.addPath(path)
            context.fillPath()
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
            guard var current = sortedLineRects.first else { continue }

            for rect in sortedLineRects.dropFirst() {
                let maxGap = max(3, min(current.height, rect.height) * 0.5)
                if rect.minX - current.maxX <= maxGap {
                    current = current.union(rect)
                } else {
                    merged.append(current)
                    current = rect
                }
            }
            merged.append(current)
        }

        return merged
    }
}
