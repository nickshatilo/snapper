import AppKit
import SwiftUI

struct ToolOptionsView: View {
    @Bindable var canvasState: CanvasState
    @Bindable var toolManager: ToolManager
    @State private var hoveredTool: ToolType?
    private let textSizeRange: ClosedRange<CGFloat> = 8...240

    private enum AnnotationSelectionMode {
        case none
        case single(annotation: any Annotation)
        case multipleSameType(primary: any Annotation, count: Int)
        case multipleMixed(count: Int)
    }

    var body: some View {
        HStack(spacing: 16) {
            switch primaryGroup {
            case .mouse:
                switch selectionMode {
                case .none:
                    Label(
                        "Mouse mode: select, move, resize, and double-click text to edit.",
                        systemImage: "cursorarrow"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                case .single(let annotation):
                    selectedAnnotationEditor(annotation)

                case .multipleSameType(let primary, let count):
                    Label("\(count) \(annotationTypeLabel(for: primary)) selected", systemImage: "square.on.square")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    selectedAnnotationEditor(primary)

                case .multipleMixed(let count):
                    Label(
                        "\(count) items selected. Move works for all; property editing works when all selected items share one type.",
                        systemImage: "square.on.square"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

            case .ocr:
                Label("OCR mode: drag over text and press Cmd+C to copy.", systemImage: "text.viewfinder")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .hand:
                Label("Hand mode: drag to pan around the image.", systemImage: "hand.draw")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .text:
                colorControls(textColorBinding)
                fontPicker(textFontNameBinding)
                sliderWithNumericInput(
                    label: "Size:",
                    value: textFontSizeBinding,
                    in: textSizeRange
                )

            case .draw:
                iconToolPicker(group: .draw)
                colorControls
                strokeWidthControls

            case .shapes:
                iconToolPicker(group: .shapes)
                colorControls
                if showsStrokeWidth {
                    strokeWidthControls
                }

                switch toolManager.currentTool {
                case .arrow:
                    Picker("Style", selection: $toolManager.arrowStyle) {
                        ForEach(ArrowStyle.allCases, id: \.self) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .frame(width: 120)

                case .rectangle:
                    rectangleFillOptions

                    HStack(spacing: 4) {
                        Text("Radius:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(value: $toolManager.cornerRadius, in: 0...30)
                            .frame(width: 80)
                    }

                case .ellipse:
                    ellipseFillOptions

                case .line:
                    Toggle("Dashed", isOn: $toolManager.isDashed)

                case .counter:
                    Picker("Style", selection: $toolManager.counterStyle) {
                        ForEach(CounterStyle.allCases, id: \.self) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .frame(width: 120)

                default:
                    EmptyView()
                }

            case .blur:
                iconToolPicker(group: .blur)

                switch toolManager.currentTool {
                case .blur:
                    HStack(spacing: 4) {
                        Text("Intensity:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(value: $toolManager.blurIntensity, in: 1...50)
                            .frame(width: 100)
                    }

                case .pixelate:
                    HStack(spacing: 4) {
                        Text("Block size:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(value: $toolManager.pixelateBlockSize, in: 4...40)
                            .frame(width: 100)
                    }

                default:
                    EmptyView()
                }

            case .crop:
                Label("Resize/move the crop box directly, then apply.", systemImage: "crop")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Apply Crop") {
                    if canvasState.applyActiveCrop() {
                        toolManager.currentTool = .textSelect
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [])
            }

            Spacer()
        }
        .padding(.horizontal, 12)
    }

    private var primaryGroup: PrimaryToolGroup {
        toolManager.currentTool.primaryGroup
    }

    private var selectedAnnotation: (any Annotation)? {
        guard let selectedAnnotationID = canvasState.selectedAnnotationID else {
            return selectedAnnotations.first
        }
        return canvasState.annotations.first(where: { $0.id == selectedAnnotationID })
            ?? selectedAnnotations.first
    }

    private var selectedAnnotations: [any Annotation] {
        canvasState.selectedAnnotations()
    }

    private var editableSelectedAnnotations: [any Annotation] {
        guard let selectedAnnotation else { return [] }
        let annotations = selectedAnnotations
        guard !annotations.isEmpty else { return [] }

        let selectedType = ObjectIdentifier(type(of: selectedAnnotation))
        guard annotations.allSatisfy({ ObjectIdentifier(type(of: $0)) == selectedType }) else {
            return []
        }

        return [selectedAnnotation] + annotations.filter { $0.id != selectedAnnotation.id }
    }

    private var selectionMode: AnnotationSelectionMode {
        let annotations = selectedAnnotations
        guard let selectedAnnotation else { return .none }

        if annotations.count <= 1 {
            return .single(annotation: selectedAnnotation)
        }

        let selectedType = ObjectIdentifier(type(of: selectedAnnotation))
        let isSameTypeSelection = annotations.allSatisfy {
            ObjectIdentifier(type(of: $0)) == selectedType
        }

        if isSameTypeSelection {
            return .multipleSameType(primary: selectedAnnotation, count: annotations.count)
        }

        return .multipleMixed(count: annotations.count)
    }

    private func annotationTypeLabel(for annotation: any Annotation) -> String {
        if annotation is TextAnnotation { return "text item(s)" }
        if annotation is ArrowAnnotation { return "arrow(s)" }
        if annotation is RectangleAnnotation { return "rectangle(s)" }
        if annotation is EllipseAnnotation { return "ellipse(s)" }
        if annotation is LineAnnotation { return "line(s)" }
        if annotation is PencilAnnotation { return "pencil stroke(s)" }
        if annotation is HighlighterAnnotation { return "highlight(s)" }
        if annotation is CounterAnnotation { return "counter(s)" }
        if annotation is BlurAnnotation { return "blur area(s)" }
        if annotation is PixelateAnnotation { return "pixelate area(s)" }
        if annotation is SpotlightAnnotation { return "spotlight area(s)" }
        if annotation is CropAnnotation { return "crop area(s)" }
        return "item(s)"
    }

    @ViewBuilder
    private func selectedAnnotationEditor(_ annotation: any Annotation) -> some View {
        if let text = annotation as? TextAnnotation {
            selectedTextEditor(text)
        } else if let arrow = annotation as? ArrowAnnotation {
            selectedArrowEditor(arrow)
        } else if let rectangle = annotation as? RectangleAnnotation {
            selectedRectangleEditor(rectangle)
        } else if let ellipse = annotation as? EllipseAnnotation {
            selectedEllipseEditor(ellipse)
        } else if let line = annotation as? LineAnnotation {
            selectedLineEditor(line)
        } else if let pencil = annotation as? PencilAnnotation {
            selectedStrokeEditor(
                title: "Pencil",
                iconName: "pencil",
                fallbackColor: pencil.color,
                fallbackWidth: pencil.strokeWidth,
                colorGet: { ($0 as? PencilAnnotation)?.color },
                widthGet: { ($0 as? PencilAnnotation)?.strokeWidth },
                update: { annotation, color, width in
                    guard let pencil = annotation as? PencilAnnotation else { return nil }
                    return PencilAnnotation(
                        id: pencil.id,
                        points: pencil.points,
                        color: color,
                        strokeWidth: width
                    )
                }
            )
        } else if let highlighter = annotation as? HighlighterAnnotation {
            selectedStrokeEditor(
                title: "Highlighter",
                iconName: "highlighter",
                fallbackColor: highlighter.color,
                fallbackWidth: highlighter.strokeWidth,
                colorGet: { ($0 as? HighlighterAnnotation)?.color },
                widthGet: { ($0 as? HighlighterAnnotation)?.strokeWidth },
                update: { annotation, color, width in
                    guard let highlighter = annotation as? HighlighterAnnotation else { return nil }
                    return HighlighterAnnotation(
                        id: highlighter.id,
                        start: highlighter.start,
                        end: highlighter.end,
                        color: color,
                        strokeWidth: width
                    )
                }
            )
        } else if let counter = annotation as? CounterAnnotation {
            selectedCounterEditor(counter)
        } else if let blur = annotation as? BlurAnnotation {
            selectedBlurEditor(blur)
        } else if let pixelate = annotation as? PixelateAnnotation {
            selectedPixelateEditor(pixelate)
        } else if let spotlight = annotation as? SpotlightAnnotation {
            selectedSpotlightEditor(spotlight)
        } else if let crop = annotation as? CropAnnotation {
            selectedCropEditor(crop)
        } else {
            Label("Selected object is editable by drag handles.", systemImage: "cursorarrow")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func selectedTextEditor(_ text: TextAnnotation) -> some View {
        Label("Text", systemImage: "textformat")
            .font(.caption)
            .foregroundStyle(.secondary)

        TextField(
            "Text",
            text: selectedBinding(
                fallback: text.text,
                get: { ($0 as? TextAnnotation)?.text },
                set: { annotation, value in
                    guard let text = annotation as? TextAnnotation else { return nil }
                    return makeTextAnnotation(from: text, text: value)
                }
            )
        )
        .frame(width: 180)

        colorControls(
            selectedBinding(
                fallback: text.color,
                get: { ($0 as? TextAnnotation)?.color },
                set: { annotation, value in
                    guard let text = annotation as? TextAnnotation else { return nil }
                    return makeTextAnnotation(from: text, color: value)
                }
            )
        )

        fontPicker(
            selectedBinding(
                fallback: text.fontName,
                get: { ($0 as? TextAnnotation)?.fontName },
                set: { annotation, value in
                    guard let text = annotation as? TextAnnotation else { return nil }
                    return makeTextAnnotation(from: text, fontName: value)
                }
            )
        )

        let sizeBinding = selectedBinding(
            fallback: text.fontSize,
            get: { ($0 as? TextAnnotation)?.fontSize },
            set: { annotation, value in
                guard let text = annotation as? TextAnnotation else { return nil }
                return makeTextAnnotation(from: text, fontSize: value)
            }
        )
        sliderWithNumericInput(
            label: "Size:",
            value: sizeBinding,
            in: textSizeRange
        )
    }

    @ViewBuilder
    private func selectedArrowEditor(_ arrow: ArrowAnnotation) -> some View {
        Label("Arrow", systemImage: "arrow.up.right")
            .font(.caption)
            .foregroundStyle(.secondary)

        colorControls(
            selectedBinding(
                fallback: arrow.color,
                get: { ($0 as? ArrowAnnotation)?.color },
                set: { annotation, value in
                    guard let arrow = annotation as? ArrowAnnotation else { return nil }
                    return ArrowAnnotation(
                        id: arrow.id,
                        start: arrow.start,
                        end: arrow.end,
                        color: value,
                        strokeWidth: arrow.strokeWidth,
                        style: arrow.style
                    )
                }
            )
        )

        strokeWidthControls(
            selectedBinding(
                fallback: arrow.strokeWidth,
                get: { ($0 as? ArrowAnnotation)?.strokeWidth },
                set: { annotation, value in
                    guard let arrow = annotation as? ArrowAnnotation else { return nil }
                    return ArrowAnnotation(
                        id: arrow.id,
                        start: arrow.start,
                        end: arrow.end,
                        color: arrow.color,
                        strokeWidth: value,
                        style: arrow.style
                    )
                }
            )
        )

        Picker(
            "Style",
            selection: selectedBinding(
                fallback: arrow.style,
                get: { ($0 as? ArrowAnnotation)?.style },
                set: { annotation, value in
                    guard let arrow = annotation as? ArrowAnnotation else { return nil }
                    return ArrowAnnotation(
                        id: arrow.id,
                        start: arrow.start,
                        end: arrow.end,
                        color: arrow.color,
                        strokeWidth: arrow.strokeWidth,
                        style: value
                    )
                }
            )
        ) {
            ForEach(ArrowStyle.allCases, id: \.self) { style in
                Text(style.displayName).tag(style)
            }
        }
        .frame(width: 120)
    }

    @ViewBuilder
    private func selectedRectangleEditor(_ rectangle: RectangleAnnotation) -> some View {
        Label("Rectangle", systemImage: "rectangle")
            .font(.caption)
            .foregroundStyle(.secondary)

        colorControls(
            selectedBinding(
                fallback: rectangle.strokeColor,
                get: { ($0 as? RectangleAnnotation)?.strokeColor },
                set: { annotation, value in
                    guard let rectangle = annotation as? RectangleAnnotation else { return nil }
                    return RectangleAnnotation(
                        id: rectangle.id,
                        rect: rectangle.rect,
                        strokeColor: value,
                        fillColor: rectangle.fillColor,
                        strokeWidth: rectangle.strokeWidth,
                        cornerRadius: rectangle.cornerRadius,
                        rotationDegrees: rectangle.rotationDegrees
                    )
                }
            )
        )

        strokeWidthControls(
            selectedBinding(
                fallback: rectangle.strokeWidth,
                get: { ($0 as? RectangleAnnotation)?.strokeWidth },
                set: { annotation, value in
                    guard let rectangle = annotation as? RectangleAnnotation else { return nil }
                    return RectangleAnnotation(
                        id: rectangle.id,
                        rect: rectangle.rect,
                        strokeColor: rectangle.strokeColor,
                        fillColor: rectangle.fillColor,
                        strokeWidth: value,
                        cornerRadius: rectangle.cornerRadius,
                        rotationDegrees: rectangle.rotationDegrees
                    )
                }
            )
        )

        let fillEnabledBinding = selectedBinding(
            fallback: rectangle.fillColor != nil,
            get: { ($0 as? RectangleAnnotation).map { $0.fillColor != nil } },
            set: { annotation, value in
                guard let rectangle = annotation as? RectangleAnnotation else { return nil }
                let fill = value ? (rectangle.fillColor ?? rectangle.strokeColor.withAlphaComponent(0.3)) : nil
                return RectangleAnnotation(
                    id: rectangle.id,
                    rect: rectangle.rect,
                    strokeColor: rectangle.strokeColor,
                    fillColor: fill,
                    strokeWidth: rectangle.strokeWidth,
                    cornerRadius: rectangle.cornerRadius,
                    rotationDegrees: rectangle.rotationDegrees
                )
            }
        )
        Toggle("Fill", isOn: fillEnabledBinding)

        if fillEnabledBinding.wrappedValue {
            colorControls(
                selectedBinding(
                    fallback: rectangle.fillColor ?? rectangle.strokeColor.withAlphaComponent(0.3),
                    get: { annotation in
                        guard let rectangle = annotation as? RectangleAnnotation else { return nil }
                        return rectangle.fillColor ?? rectangle.strokeColor.withAlphaComponent(0.3)
                    },
                    set: { annotation, value in
                        guard let rectangle = annotation as? RectangleAnnotation else { return nil }
                        return RectangleAnnotation(
                            id: rectangle.id,
                            rect: rectangle.rect,
                            strokeColor: rectangle.strokeColor,
                            fillColor: value,
                            strokeWidth: rectangle.strokeWidth,
                            cornerRadius: rectangle.cornerRadius,
                            rotationDegrees: rectangle.rotationDegrees
                        )
                    }
                ),
                label: "Fill:"
            )
        }

        HStack(spacing: 4) {
            Text("Radius:")
                .font(.caption)
                .foregroundStyle(.secondary)
            Slider(
                value: selectedBinding(
                    fallback: rectangle.cornerRadius,
                    get: { ($0 as? RectangleAnnotation)?.cornerRadius },
                    set: { annotation, value in
                        guard let rectangle = annotation as? RectangleAnnotation else { return nil }
                        return RectangleAnnotation(
                            id: rectangle.id,
                            rect: rectangle.rect,
                            strokeColor: rectangle.strokeColor,
                            fillColor: rectangle.fillColor,
                            strokeWidth: rectangle.strokeWidth,
                            cornerRadius: value,
                            rotationDegrees: rectangle.rotationDegrees
                        )
                    }
                ),
                in: 0...30
            )
            .frame(width: 80)
        }
    }

    @ViewBuilder
    private func selectedEllipseEditor(_ ellipse: EllipseAnnotation) -> some View {
        Label("Ellipse", systemImage: "circle")
            .font(.caption)
            .foregroundStyle(.secondary)

        colorControls(
            selectedBinding(
                fallback: ellipse.strokeColor,
                get: { ($0 as? EllipseAnnotation)?.strokeColor },
                set: { annotation, value in
                    guard let ellipse = annotation as? EllipseAnnotation else { return nil }
                    return EllipseAnnotation(
                        id: ellipse.id,
                        rect: ellipse.rect,
                        strokeColor: value,
                        fillColor: ellipse.fillColor,
                        strokeWidth: ellipse.strokeWidth,
                        rotationDegrees: ellipse.rotationDegrees
                    )
                }
            )
        )

        strokeWidthControls(
            selectedBinding(
                fallback: ellipse.strokeWidth,
                get: { ($0 as? EllipseAnnotation)?.strokeWidth },
                set: { annotation, value in
                    guard let ellipse = annotation as? EllipseAnnotation else { return nil }
                    return EllipseAnnotation(
                        id: ellipse.id,
                        rect: ellipse.rect,
                        strokeColor: ellipse.strokeColor,
                        fillColor: ellipse.fillColor,
                        strokeWidth: value,
                        rotationDegrees: ellipse.rotationDegrees
                    )
                }
            )
        )

        let fillEnabledBinding = selectedBinding(
            fallback: ellipse.fillColor != nil,
            get: { ($0 as? EllipseAnnotation).map { $0.fillColor != nil } },
            set: { annotation, value in
                guard let ellipse = annotation as? EllipseAnnotation else { return nil }
                let fill = value ? (ellipse.fillColor ?? ellipse.strokeColor.withAlphaComponent(0.3)) : nil
                return EllipseAnnotation(
                    id: ellipse.id,
                    rect: ellipse.rect,
                    strokeColor: ellipse.strokeColor,
                    fillColor: fill,
                    strokeWidth: ellipse.strokeWidth,
                    rotationDegrees: ellipse.rotationDegrees
                )
            }
        )
        Toggle("Fill", isOn: fillEnabledBinding)

        if fillEnabledBinding.wrappedValue {
            colorControls(
                selectedBinding(
                    fallback: ellipse.fillColor ?? ellipse.strokeColor.withAlphaComponent(0.3),
                    get: { annotation in
                        guard let ellipse = annotation as? EllipseAnnotation else { return nil }
                        return ellipse.fillColor ?? ellipse.strokeColor.withAlphaComponent(0.3)
                    },
                    set: { annotation, value in
                        guard let ellipse = annotation as? EllipseAnnotation else { return nil }
                        return EllipseAnnotation(
                            id: ellipse.id,
                            rect: ellipse.rect,
                            strokeColor: ellipse.strokeColor,
                            fillColor: value,
                            strokeWidth: ellipse.strokeWidth,
                            rotationDegrees: ellipse.rotationDegrees
                        )
                    }
                ),
                label: "Fill:"
            )
        }
    }

    @ViewBuilder
    private func selectedLineEditor(_ line: LineAnnotation) -> some View {
        Label("Line", systemImage: "line.diagonal")
            .font(.caption)
            .foregroundStyle(.secondary)

        colorControls(
            selectedBinding(
                fallback: line.color,
                get: { ($0 as? LineAnnotation)?.color },
                set: { annotation, value in
                    guard let line = annotation as? LineAnnotation else { return nil }
                    return LineAnnotation(
                        id: line.id,
                        start: line.start,
                        end: line.end,
                        color: value,
                        strokeWidth: line.strokeWidth,
                        isDashed: line.isDashed
                    )
                }
            )
        )

        strokeWidthControls(
            selectedBinding(
                fallback: line.strokeWidth,
                get: { ($0 as? LineAnnotation)?.strokeWidth },
                set: { annotation, value in
                    guard let line = annotation as? LineAnnotation else { return nil }
                    return LineAnnotation(
                        id: line.id,
                        start: line.start,
                        end: line.end,
                        color: line.color,
                        strokeWidth: value,
                        isDashed: line.isDashed
                    )
                }
            )
        )

        Toggle(
            "Dashed",
            isOn: selectedBinding(
                fallback: line.isDashed,
                get: { ($0 as? LineAnnotation)?.isDashed },
                set: { annotation, value in
                    guard let line = annotation as? LineAnnotation else { return nil }
                    return LineAnnotation(
                        id: line.id,
                        start: line.start,
                        end: line.end,
                        color: line.color,
                        strokeWidth: line.strokeWidth,
                        isDashed: value
                    )
                }
            )
        )
    }

    @ViewBuilder
    private func selectedStrokeEditor(
        title: String,
        iconName: String,
        fallbackColor: NSColor,
        fallbackWidth: CGFloat,
        colorGet: @escaping ((any Annotation) -> NSColor?),
        widthGet: @escaping ((any Annotation) -> CGFloat?),
        update: @escaping ((any Annotation, NSColor, CGFloat) -> (any Annotation)?)
    ) -> some View {
        Label(title, systemImage: iconName)
            .font(.caption)
            .foregroundStyle(.secondary)

        let colorBinding = selectedBinding(
            fallback: fallbackColor,
            get: colorGet,
            set: { annotation, color in
                update(annotation, color, widthGet(annotation) ?? fallbackWidth)
            }
        )

        let widthBinding = selectedBinding(
            fallback: fallbackWidth,
            get: widthGet,
            set: { annotation, width in
                update(annotation, colorGet(annotation) ?? fallbackColor, width)
            }
        )

        colorControls(colorBinding)
        strokeWidthControls(widthBinding)
    }

    @ViewBuilder
    private func selectedCounterEditor(_ counter: CounterAnnotation) -> some View {
        Label("Counter", systemImage: "number")
            .font(.caption)
            .foregroundStyle(.secondary)

        colorControls(
            selectedBinding(
                fallback: counter.color,
                get: { ($0 as? CounterAnnotation)?.color },
                set: { annotation, value in
                    guard let counter = annotation as? CounterAnnotation else { return nil }
                    return CounterAnnotation(
                        id: counter.id,
                        position: counter.position,
                        value: counter.value,
                        style: counter.style,
                        color: value
                    )
                }
            )
        )

        Picker(
            "Style",
            selection: selectedBinding(
                fallback: counter.style,
                get: { ($0 as? CounterAnnotation)?.style },
                set: { annotation, value in
                    guard let counter = annotation as? CounterAnnotation else { return nil }
                    return CounterAnnotation(
                        id: counter.id,
                        position: counter.position,
                        value: counter.value,
                        style: value,
                        color: counter.color
                    )
                }
            )
        ) {
            ForEach(CounterStyle.allCases, id: \.self) { style in
                Text(style.displayName).tag(style)
            }
        }
        .frame(width: 120)
    }

    @ViewBuilder
    private func selectedBlurEditor(_ blur: BlurAnnotation) -> some View {
        Label("Blur", systemImage: "drop.halffull")
            .font(.caption)
            .foregroundStyle(.secondary)

        let intensityBinding = selectedBinding(
            fallback: blur.intensity,
            get: { ($0 as? BlurAnnotation)?.intensity },
            set: { annotation, value in
                guard let blur = annotation as? BlurAnnotation else { return nil }
                return BlurAnnotation(
                    id: blur.id,
                    rect: blur.rect,
                    intensity: value,
                    sourceImage: blur.sourceImage
                )
            }
        )

        HStack(spacing: 4) {
            Text("Intensity:")
                .font(.caption)
                .foregroundStyle(.secondary)
            Slider(value: intensityBinding, in: 1...50)
                .frame(width: 100)
        }
    }

    @ViewBuilder
    private func selectedPixelateEditor(_ pixelate: PixelateAnnotation) -> some View {
        Label("Pixelate", systemImage: "squareshape.split.3x3")
            .font(.caption)
            .foregroundStyle(.secondary)

        let blockSizeBinding = selectedBinding(
            fallback: pixelate.blockSize,
            get: { ($0 as? PixelateAnnotation)?.blockSize },
            set: { annotation, value in
                guard let pixelate = annotation as? PixelateAnnotation else { return nil }
                return PixelateAnnotation(
                    id: pixelate.id,
                    rect: pixelate.rect,
                    blockSize: value,
                    sourceImage: pixelate.sourceImage
                )
            }
        )

        HStack(spacing: 4) {
            Text("Block size:")
                .font(.caption)
                .foregroundStyle(.secondary)
            Slider(value: blockSizeBinding, in: 4...40)
                .frame(width: 100)
        }
    }

    @ViewBuilder
    private func selectedSpotlightEditor(_ spotlight: SpotlightAnnotation) -> some View {
        Label("Spotlight", systemImage: "flashlight.on.fill")
            .font(.caption)
            .foregroundStyle(.secondary)

        let dimBinding = selectedBinding(
            fallback: spotlight.dimOpacity,
            get: { ($0 as? SpotlightAnnotation)?.dimOpacity },
            set: { annotation, value in
                guard let spotlight = annotation as? SpotlightAnnotation else { return nil }
                return SpotlightAnnotation(
                    id: spotlight.id,
                    rect: spotlight.rect,
                    dimOpacity: value
                )
            }
        )

        HStack(spacing: 4) {
            Text("Dim:")
                .font(.caption)
                .foregroundStyle(.secondary)
            Slider(value: dimBinding, in: 0.1...0.9)
                .frame(width: 100)
        }
    }

    @ViewBuilder
    private func selectedCropEditor(_ crop: CropAnnotation) -> some View {
        Label("Crop", systemImage: "crop")
            .font(.caption)
            .foregroundStyle(.secondary)

        Text("Size: \(Int(crop.rect.width)) × \(Int(crop.rect.height))")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func selectedBinding<Value>(
        fallback: @autoclosure @escaping () -> Value,
        get: @escaping ((any Annotation) -> Value?),
        set: @escaping ((any Annotation, Value) -> (any Annotation)?),
        onSet: ((Value) -> Void)? = nil
    ) -> Binding<Value> {
        Binding(
            get: {
                guard let selectedAnnotation = editableSelectedAnnotations.first else {
                    return fallback()
                }
                return get(selectedAnnotation) ?? fallback()
            },
            set: { newValue in
                onSet?(newValue)
                applyToEditableSelectedAnnotations { annotation in
                    set(annotation, newValue)
                }
            }
        )
    }

    private func applyToEditableSelectedAnnotations(
        _ transform: ((any Annotation) -> (any Annotation)?)
    ) {
        let annotations = editableSelectedAnnotations
        guard !annotations.isEmpty else { return }

        let primaryID = canvasState.selectedAnnotationID
        var didApplyUpdate = false

        for source in annotations {
            guard let updated = transform(source) else { continue }
            updated.zOrder = source.zOrder
            updated.isVisible = source.isVisible
            canvasState.replaceAnnotation(updated, recordUndo: true)
            didApplyUpdate = true
        }

        guard didApplyUpdate else { return }

        let selectionIDs = Set(annotations.map { $0.id })
        canvasState.selectedAnnotationIDs = selectionIDs
        if let primaryID, selectionIDs.contains(primaryID) {
            canvasState.selectedAnnotationID = primaryID
        } else {
            canvasState.selectedAnnotationID = annotations.first?.id
        }
    }

    private func makeTextAnnotation(
        from source: TextAnnotation,
        text: String? = nil,
        fontName: String? = nil,
        fontSize: CGFloat? = nil,
        color: NSColor? = nil
    ) -> TextAnnotation {
        let updated = TextAnnotation(
            id: source.id,
            position: source.position,
            text: text ?? source.text,
            fontName: fontName ?? source.fontName,
            fontSize: fontSize ?? source.fontSize,
            color: color ?? source.color,
            rotationDegrees: source.rotationDegrees
        )
        updated.isBold = source.isBold
        updated.isItalic = source.isItalic
        updated.hasBackground = source.hasBackground
        return updated
    }

    private var colorControls: some View {
        colorControls($toolManager.strokeColor)
    }

    private var textColorBinding: Binding<NSColor> {
        selectedBinding(
            fallback: toolManager.strokeColor,
            get: { ($0 as? TextAnnotation)?.color },
            set: { annotation, value in
                guard let text = annotation as? TextAnnotation else { return nil }
                return makeTextAnnotation(from: text, color: value)
            },
            onSet: { newValue in
                toolManager.strokeColor = newValue
            }
        )
    }

    private var textFontNameBinding: Binding<String> {
        selectedBinding(
            fallback: toolManager.fontName,
            get: { ($0 as? TextAnnotation)?.fontName },
            set: { annotation, value in
                guard let text = annotation as? TextAnnotation else { return nil }
                return makeTextAnnotation(from: text, fontName: value)
            },
            onSet: { newValue in
                toolManager.fontName = newValue
            }
        )
    }

    private var textFontSizeBinding: Binding<CGFloat> {
        selectedBinding(
            fallback: toolManager.fontSize,
            get: { ($0 as? TextAnnotation)?.fontSize },
            set: { annotation, value in
                guard let text = annotation as? TextAnnotation else { return nil }
                return makeTextAnnotation(from: text, fontSize: value)
            },
            onSet: { newValue in
                toolManager.fontSize = newValue
            }
        )
    }

    private func colorControls(_ colorBinding: Binding<NSColor>, label: String = "Color:") -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            InlineColorPickerButton(selectedColor: colorBinding)
        }
    }

    private var strokeWidthControls: some View {
        strokeWidthControls($toolManager.strokeWidth)
    }

    private func strokeWidthControls(_ widthBinding: Binding<CGFloat>) -> some View {
        sliderWithNumericInput(label: "Width:", value: widthBinding, in: 1...20)
    }

    private func fontPicker(_ selection: Binding<String>) -> some View {
        let fonts = fontOptions(including: selection.wrappedValue)
        return Picker("Font", selection: selection) {
            ForEach(fonts, id: \.self) { fontName in
                Text(fontName).tag(fontName)
            }
        }
        .pickerStyle(.menu)
        .frame(width: 170)
    }

    private func fontOptions(including currentSelection: String) -> [String] {
        var fonts = NSFontManager.shared.availableFontFamilies
            .filter { !$0.isEmpty }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        if !currentSelection.isEmpty && !fonts.contains(currentSelection) {
            fonts.insert(currentSelection, at: 0)
        }
        return fonts
    }

    private func sliderWithNumericInput(
        label: String,
        value: Binding<CGFloat>,
        in range: ClosedRange<CGFloat>
    ) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Slider(value: value, in: range, step: 1)
                .frame(width: 100)
            TextField(
                "",
                value: numericInputBinding(for: value, in: range),
                format: .number.precision(.fractionLength(0))
            )
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .frame(width: 52)
        }
    }

    private func numericInputBinding(
        for value: Binding<CGFloat>,
        in range: ClosedRange<CGFloat>
    ) -> Binding<Double> {
        Binding<Double>(
            get: { Double(value.wrappedValue) },
            set: { newValue in
                let clamped = min(max(CGFloat(newValue), range.lowerBound), range.upperBound)
                value.wrappedValue = clamped
            }
        )
    }

    private func iconToolPicker(group: PrimaryToolGroup) -> some View {
        let availableTools = ToolType.tools(for: group)
        return HStack(spacing: 6) {
            ForEach(availableTools, id: \.self) { tool in
                let isSelected = toolManager.currentTool == tool
                let isHovered = hoveredTool == tool

                Button {
                    toolManager.currentTool = tool
                } label: {
                    Image(systemName: tool.iconName)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 26, height: 24)
                        .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(isHovered ? 0.95 : 0.72))
                        .background {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: isSelected
                                            ? [Color.accentColor.opacity(0.95), Color.accentColor.opacity(0.70)]
                                            : [Color.primary.opacity(isHovered ? 0.14 : 0.09), Color.primary.opacity(isHovered ? 0.05 : 0.03)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        .overlay {
                            if isHovered && !isSelected {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(Color.accentColor.opacity(0.30), lineWidth: 1)
                            }
                        }
                        .shadow(color: isSelected ? Color.accentColor.opacity(0.30) : .clear, radius: 4, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                .help(tool.displayName)
                .onHover { hovering in
                    if hovering {
                        hoveredTool = tool
                    } else if hoveredTool == tool {
                        hoveredTool = nil
                    }
                }
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private var showsStrokeWidth: Bool {
        switch toolManager.currentTool {
        case .arrow, .rectangle, .ellipse, .line, .pencil, .highlighter:
            return true
        default:
            return false
        }
    }

    private var rectangleFillOptions: some View {
        fillOptions(label: "Fill")
    }

    private var ellipseFillOptions: some View {
        fillOptions(label: "Fill")
    }

    @ViewBuilder
    private func fillOptions(label: String) -> some View {
        Toggle(label, isOn: Binding(
            get: { toolManager.fillColor != nil },
            set: { isEnabled in
                if isEnabled {
                    let opacity = min(max(toolManager.fillOpacity, 0), 1)
                    toolManager.fillColor = toolManager.strokeColor.withAlphaComponent(opacity)
                } else {
                    toolManager.fillColor = nil
                }
            }
        ))

        if toolManager.fillColor != nil {
            HStack(spacing: 8) {
                Text("Fill:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                InlineColorPickerButton(selectedColor: fillColorBinding)
            }
        }
    }

    private var fillColorBinding: Binding<NSColor> {
        Binding(
            get: {
                toolManager.fillColor ?? toolManager.strokeColor.withAlphaComponent(min(max(toolManager.fillOpacity, 0), 1))
            },
            set: { newColor in
                toolManager.fillColor = newColor
                toolManager.fillOpacity = newColor.alphaComponent
            }
        )
    }

}

private struct InlineColorPickerButton: View {
    @Binding var selectedColor: NSColor
    @State private var isPickerPresented = false

    var body: some View {
        Button {
            isPickerPresented.toggle()
        } label: {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color(nsColor: selectedColor))
                    .overlay {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.25), lineWidth: 1)
                    }
                    .frame(width: 26, height: 16)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPickerPresented, arrowEdge: .bottom) {
            InlineHSBColorPicker(selectedColor: $selectedColor)
                .padding(12)
        }
    }
}

private struct InlineHSBColorPicker: View {
    @Binding var selectedColor: NSColor
    @State private var hue: CGFloat = 0
    @State private var saturation: CGFloat = 1
    @State private var brightness: CGFloat = 1
    @State private var opacity: CGFloat = 1
    @State private var isSynchronizing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pick Color")
                .font(.caption)
                .foregroundStyle(.secondary)

            SaturationBrightnessField(
                hue: hue,
                saturation: $saturation,
                brightness: $brightness
            )
            .frame(width: 180, height: 120)

            HueField(hue: $hue)
                .frame(width: 180, height: 14)

            HStack(spacing: 8) {
                Text("Opacity")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .leading)
                Slider(value: $opacity, in: 0...1)
                    .frame(width: 110)
                Text("\(Int(opacity * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }
        }
        .onAppear {
            syncFromSelectedColor()
        }
        .onChange(of: hue) { _, _ in
            applyColor()
        }
        .onChange(of: saturation) { _, _ in
            applyColor()
        }
        .onChange(of: brightness) { _, _ in
            applyColor()
        }
        .onChange(of: opacity) { _, _ in
            applyColor()
        }
    }

    private func syncFromSelectedColor() {
        guard !isSynchronizing else { return }
        isSynchronizing = true

        let rgb = selectedColor.usingColorSpace(.deviceRGB) ?? selectedColor
        var h: CGFloat = 0
        var s: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 1
        rgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        hue = h
        saturation = s
        brightness = b
        opacity = a

        isSynchronizing = false
    }

    private func applyColor() {
        guard !isSynchronizing else { return }
        selectedColor = NSColor(
            calibratedHue: clamp01(hue),
            saturation: clamp01(saturation),
            brightness: clamp01(brightness),
            alpha: clamp01(opacity)
        )
    }

    private func clamp01(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }
}

private struct SaturationBrightnessField: View {
    let hue: CGFloat
    @Binding var saturation: CGFloat
    @Binding var brightness: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let knobX = min(max(saturation * width, 0), width)
            let knobY = min(max((1 - brightness) * height, 0), height)

            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: NSColor(calibratedHue: hue, saturation: 1, brightness: 1, alpha: 1)))

                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.white, .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )

                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.clear, .black],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                Circle()
                    .strokeBorder(Color.white.opacity(0.95), lineWidth: 2)
                    .background(Circle().fill(Color.clear))
                    .frame(width: 12, height: 12)
                    .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                    .position(x: knobX, y: knobY)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.28), lineWidth: 1)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let x = min(max(value.location.x, 0), width)
                        let y = min(max(value.location.y, 0), height)
                        saturation = width > 0 ? (x / width) : 0
                        brightness = height > 0 ? (1 - y / height) : 1
                    }
            )
        }
    }
}

private struct HueField: View {
    @Binding var hue: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let knobX = min(max(hue * width, 0), width)

            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )

                Circle()
                    .strokeBorder(Color.white.opacity(0.95), lineWidth: 2)
                    .background(Circle().fill(Color.clear))
                    .frame(width: 12, height: 12)
                    .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                    .position(x: knobX, y: proxy.size.height / 2)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.28), lineWidth: 1)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let x = min(max(value.location.x, 0), width)
                        hue = width > 0 ? (x / width) : 0
                    }
            )
        }
    }
}
