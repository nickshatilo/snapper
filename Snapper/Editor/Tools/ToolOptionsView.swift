import SwiftUI

struct ToolOptionsView: View {
    @Bindable var toolManager: ToolManager
    private let colorPresets: [NSColor] = [
        .systemRed, .systemOrange, .systemYellow, .systemGreen,
        .systemTeal, .systemBlue, .systemIndigo, .systemPurple,
        .systemPink, .white, .black,
    ]

    var body: some View {
        HStack(spacing: 16) {
            if toolManager.currentTool == .textSelect {
                Label("Text Select mode: drag over text, then press Cmd+C to copy.", systemImage: "text.cursor")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if toolManager.currentTool == .hand {
                Label("Hand mode: drag to pan around the image.", systemImage: "hand.draw")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                // Inline color swatches (avoid macOS detached color panel window)
                HStack(spacing: 8) {
                    Text("Color:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(Array(colorPresets.enumerated()), id: \.offset) { _, color in
                        ColorSwatchButton(
                            color: color,
                            isSelected: isSelected(color: color)
                        ) {
                            toolManager.strokeColor = color
                        }
                    }
                }

                // Stroke width
                if showsStrokeWidth {
                    HStack(spacing: 4) {
                        Text("Width:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(value: $toolManager.strokeWidth, in: 1...20, step: 1)
                            .frame(width: 100)
                        Text("\(Int(toolManager.strokeWidth))")
                            .font(.caption)
                            .frame(width: 20)
                    }
                }

                // Tool-specific options
                switch toolManager.currentTool {
                case .arrow:
                    Picker("Style", selection: $toolManager.arrowStyle) {
                        ForEach(ArrowStyle.allCases, id: \.self) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .frame(width: 120)

                case .rectangle:
                    HStack(spacing: 4) {
                        Text("Radius:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(value: $toolManager.cornerRadius, in: 0...30)
                            .frame(width: 80)
                    }
                    Toggle("Fill", isOn: Binding(
                        get: { toolManager.fillColor != nil },
                        set: { toolManager.fillColor = $0 ? toolManager.strokeColor.withAlphaComponent(0.3) : nil }
                    ))

                case .ellipse:
                    Toggle("Fill", isOn: Binding(
                        get: { toolManager.fillColor != nil },
                        set: { toolManager.fillColor = $0 ? toolManager.strokeColor.withAlphaComponent(0.3) : nil }
                    ))

                case .line:
                    Toggle("Dashed", isOn: $toolManager.isDashed)

                case .text:
                    TextField("Font", text: $toolManager.fontName)
                        .frame(width: 100)
                    Stepper("Size: \(Int(toolManager.fontSize))", value: $toolManager.fontSize, in: 8...72)

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

                case .spotlight:
                    HStack(spacing: 4) {
                        Text("Dim:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(value: $toolManager.spotlightDimOpacity, in: 0.1...0.9)
                            .frame(width: 100)
                    }

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
            }

            Spacer()
        }
        .padding(.horizontal, 12)
    }

    private var showsStrokeWidth: Bool {
        switch toolManager.currentTool {
        case .arrow, .rectangle, .ellipse, .line, .pencil, .highlighter:
            return true
        default:
            return false
        }
    }

    private func isSelected(color: NSColor) -> Bool {
        guard let selected = toolManager.strokeColor.usingColorSpace(.deviceRGB),
              let candidate = color.usingColorSpace(.deviceRGB) else { return false }
        let tolerance: CGFloat = 0.02
        return abs(selected.redComponent - candidate.redComponent) < tolerance &&
            abs(selected.greenComponent - candidate.greenComponent) < tolerance &&
            abs(selected.blueComponent - candidate.blueComponent) < tolerance
    }
}

private struct ColorSwatchButton: View {
    let color: NSColor
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(nsColor: color))
                .frame(width: 16, height: 16)
                .overlay {
                    Circle()
                        .strokeBorder(
                            isSelected ? Color.accentColor : Color.black.opacity(isHovering ? 0.45 : 0.25),
                            lineWidth: isSelected ? 2 : 1
                        )
                }
                .scaleEffect(isHovering ? 1.08 : 1.0)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
    }
}
