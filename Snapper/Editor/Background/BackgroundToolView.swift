import SwiftUI

struct BackgroundToolView: View {
    let image: CGImage
    @State private var selectedTemplate: BackgroundTemplate = BackgroundTemplate.builtIn[0]
    @State private var padding: CGFloat = 60
    @State private var cornerRadius: CGFloat = 12
    @State private var shadowRadius: CGFloat = 20
    @State private var previewImage: NSImage?

    var body: some View {
        HStack(spacing: 0) {
            // Preview
            VStack {
                if let preview = previewImage {
                    Image(nsImage: preview)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding()
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Controls
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Background Templates")
                        .font(.headline)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 60))], spacing: 8) {
                        ForEach(BackgroundTemplate.builtIn) { template in
                            templatePreview(template)
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Padding")
                            .font(.subheadline)
                        Slider(value: $padding, in: 0...200) { _ in updatePreview() }

                        Text("Corner Radius")
                            .font(.subheadline)
                        Slider(value: $cornerRadius, in: 0...40) { _ in updatePreview() }

                        Text("Shadow")
                            .font(.subheadline)
                        Slider(value: $shadowRadius, in: 0...50) { _ in updatePreview() }
                    }

                    Divider()

                    Picker("Aspect Ratio", selection: Binding(
                        get: { selectedTemplate.aspectRatio },
                        set: { selectedTemplate.aspectRatio = $0; updatePreview() }
                    )) {
                        ForEach(BackgroundTemplate.AspectRatio.allCases, id: \.self) { ratio in
                            Text(ratio.rawValue).tag(ratio)
                        }
                    }

                    Spacer()

                    Button("Export") { exportImage() }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                }
                .padding()
            }
            .frame(width: 240)
        }
        .frame(minWidth: 700, minHeight: 500)
        .onAppear { updatePreview() }
    }

    private func templatePreview(_ template: BackgroundTemplate) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(templateFill(template))
            .frame(width: 60, height: 40)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(selectedTemplate.id == template.id ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .onTapGesture {
                selectedTemplate = template
                updatePreview()
            }
    }

    private func templateFill(_ template: BackgroundTemplate) -> some ShapeStyle {
        switch template.type {
        case .gradient(let start, let end, _):
            return AnyShapeStyle(LinearGradient(
                colors: [Color(nsColor: start.nsColor), Color(nsColor: end.nsColor)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
        case .solid(let color):
            return AnyShapeStyle(Color(nsColor: color.nsColor))
        case .image:
            return AnyShapeStyle(Color.gray)
        }
    }

    private func updatePreview() {
        var template = selectedTemplate
        template.padding = padding
        template.cornerRadius = cornerRadius
        template.shadowRadius = shadowRadius

        if let rendered = BackgroundRenderer.render(image: image, template: template) {
            previewImage = NSImage(cgImage: rendered, size: NSSize(width: rendered.width, height: rendered.height))
        }
    }

    private func exportImage() {
        var template = selectedTemplate
        template.padding = padding
        template.cornerRadius = cornerRadius
        template.shadowRadius = shadowRadius

        guard let rendered = BackgroundRenderer.render(image: image, template: template) else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "Snapper Mockup.png"
        if panel.runModal() == .OK, let url = panel.url {
            _ = ImageUtils.save(rendered, to: url, format: .png)
        }
    }
}
