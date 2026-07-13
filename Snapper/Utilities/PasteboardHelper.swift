import AppKit
import SwiftUI

enum PasteboardHelper {
    /// Copies the image as both TIFF and PNG. `scale` is the source display's
    /// backing scale; it sets the bitmap's point size so retina captures paste
    /// at their on-screen size instead of 2x.
    @discardableResult
    static func copyImage(
        _ image: CGImage,
        scale: CGFloat = 1,
        showsConfirmation: Bool = false
    ) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let bitmapRep = NSBitmapImageRep(cgImage: image)
        if scale > 0 {
            bitmapRep.size = NSSize(
                width: CGFloat(image.width) / scale,
                height: CGFloat(image.height) / scale
            )
        }

        // A single pasteboard item carries both representations; setting data
        // on NSPasteboard directly requires the type to have been declared and
        // silently drops it otherwise.
        let item = NSPasteboardItem()
        if let tiffData = bitmapRep.representation(using: .tiff, properties: [:]) {
            item.setData(tiffData, forType: .tiff)
        }
        if let pngData = bitmapRep.representation(using: .png, properties: [:]) {
            item.setData(pngData, forType: .png)
        }
        return finishCopy(
            pasteboard.writeObjects([item]),
            showsConfirmation: showsConfirmation
        )
    }

    @discardableResult
    static func copyImage(_ image: NSImage, showsConfirmation: Bool = false) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return finishCopy(
            pasteboard.writeObjects([image]),
            showsConfirmation: showsConfirmation
        )
    }

    @discardableResult
    static func copyText(_ text: String, showsConfirmation: Bool = false) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return finishCopy(
            pasteboard.setString(text, forType: .string),
            showsConfirmation: showsConfirmation
        )
    }

    @discardableResult
    static func copyFile(at url: URL, showsConfirmation: Bool = false) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return finishCopy(
            pasteboard.writeObjects([url as NSURL]),
            showsConfirmation: showsConfirmation
        )
    }

    private static func finishCopy(_ succeeded: Bool, showsConfirmation: Bool) -> Bool {
        guard succeeded, showsConfirmation else { return succeeded }
        Task { @MainActor in
            CopyConfirmationHUD.shared.show()
        }
        return true
    }
}

@MainActor
private final class CopyConfirmationHUD {
    static let shared = CopyConfirmationHUD()

    private var panel: NSPanel?
    private var dismissalTask: Task<Void, Never>?

    func show() {
        dismissalTask?.cancel()

        let panel = panel ?? makePanel()
        let hostingView = NSHostingView(rootView: CopyConfirmationHUDView())
        hostingView.frame = NSRect(origin: .zero, size: panel.frame.size)
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

        position(panel)
        panel.orderFrontRegardless()

        dismissalTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(1_350))
            } catch {
                return
            }
            panel.orderOut(nil)
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 132, height: 58),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        self.panel = panel
        return panel
    }

    private func position(_ panel: NSPanel) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) }
            ?? NSApp.keyWindow?.screen
            ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }

        panel.setFrameOrigin(
            NSPoint(
                x: visibleFrame.midX - panel.frame.width / 2,
                y: visibleFrame.maxY - panel.frame.height - 44
            )
        )
    }
}

private struct CopyConfirmationHUDView: View {
    @State private var isVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Label("Copied", systemImage: "checkmark.circle.fill")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.regularMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(.white.opacity(0.16), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.22), radius: 8, y: 3)
            .scaleEffect(isVisible || reduceMotion ? 1 : 0.84)
            .opacity(isVisible ? 1 : 0)
            .accessibilityHidden(true)
            .task {
                await Task.yield()
                guard !Task.isCancelled else { return }

                withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.24, dampingFraction: 0.72)) {
                    isVisible = true
                }

                do {
                    try await Task.sleep(for: .milliseconds(1_100))
                } catch {
                    return
                }

                withAnimation(.easeOut(duration: 0.18)) {
                    isVisible = false
                }
            }
    }
}
