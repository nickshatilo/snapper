import SwiftUI
import UniformTypeIdentifiers

struct CaptureThumbnailView: View {
    let capture: QuickAccessCapture
    let manager: QuickAccessManager
    let thumbnailWidth: CGFloat
    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(capture.thumbnail, scale: 1.0, label: Text("Screenshot"))
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: thumbnailWidth, maxHeight: 170)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.white.opacity(isHovering ? 0.28 : 0.12), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.25), radius: 6, y: 2)
                .contentShape(RoundedRectangle(cornerRadius: 10))
                .onTapGesture {
                    NotificationCenter.default.post(name: .openEditor, object: ImageWrapper(capture.image))
                    manager.removeCapture(capture.id)
                }

            if isHovering {
                actionButtons
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .onDrag {
            dragItemProvider()
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 4) {
            OverlayIconButton(icon: "doc.on.doc", tooltip: "Copy") {
                PasteboardHelper.copyImage(capture.image)
            }
            OverlayIconButton(icon: "square.and.arrow.down", tooltip: "Reveal File") {
                if let url = capture.savedURL {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
            OverlayIconButton(icon: "pencil", tooltip: "Edit") {
                NotificationCenter.default.post(name: .openEditor, object: ImageWrapper(capture.image))
                manager.removeCapture(capture.id)
            }
            OverlayIconButton(icon: "pin", tooltip: "Pin") {
                NotificationCenter.default.post(name: .pinScreenshot, object: ImageWrapper(capture.image))
                manager.removeCapture(capture.id)
            }
            OverlayIconButton(icon: "trash", tooltip: "Delete") {
                manager.removeCapture(capture.id)
                if let url = capture.savedURL {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }
        .padding(4)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(4)
    }

    private func dragItemProvider() -> NSItemProvider {
        // Prefer file URL drags when available; external apps usually preserve metadata better.
        if let savedURL = capture.savedURL {
            return NSItemProvider(object: savedURL as NSURL)
        }

        let nsImage = NSImage(
            cgImage: capture.image,
            size: NSSize(width: capture.image.width, height: capture.image.height)
        )
        let provider = NSItemProvider(object: nsImage)
        provider.suggestedName = "Snapper Screenshot"

        if let tiffData = nsImage.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            provider.registerDataRepresentation(
                forTypeIdentifier: UTType.png.identifier,
                visibility: .all
            ) { completion in
                completion(pngData, nil)
                return nil
            }
        }

        return provider
    }

}

private struct OverlayIconButton: View {
    let icon: String
    let tooltip: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 24, height: 24)
                .background(isHovering ? Color.white.opacity(0.28) : Color.black.opacity(0.26))
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hovering
            }
        }
        .help(tooltip)
    }
}

extension Notification.Name {
    static let openEditor = Notification.Name("openEditor")
    static let pinScreenshot = Notification.Name("pinScreenshot")
}
