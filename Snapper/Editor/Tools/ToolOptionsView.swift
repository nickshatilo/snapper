import AppKit
import SwiftUI

struct ToolOptionsView: View {
    @Bindable var toolManager: ToolManager

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
                HStack(spacing: 8) {
                    Text("Color:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    InlineColorPickerButton(selectedColor: $toolManager.strokeColor)
                }

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
