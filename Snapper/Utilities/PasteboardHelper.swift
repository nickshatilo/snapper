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
        showsConfirmation: Bool = false,
        confirmationScreen: NSScreen? = nil
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
            showsConfirmation: showsConfirmation,
            confirmationScreen: confirmationScreen
        )
    }

    @discardableResult
    static func copyImage(
        _ image: NSImage,
        showsConfirmation: Bool = false,
        confirmationScreen: NSScreen? = nil
    ) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return finishCopy(
            pasteboard.writeObjects([image]),
            showsConfirmation: showsConfirmation,
            confirmationScreen: confirmationScreen
        )
    }

    @discardableResult
    static func copyText(
        _ text: String,
        showsConfirmation: Bool = false,
        confirmationScreen: NSScreen? = nil
    ) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return finishCopy(
            pasteboard.setString(text, forType: .string),
            showsConfirmation: showsConfirmation,
            confirmationScreen: confirmationScreen
        )
    }

    @discardableResult
    static func copyFile(
        at url: URL,
        showsConfirmation: Bool = false,
        confirmationScreen: NSScreen? = nil
    ) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return finishCopy(
            pasteboard.writeObjects([url as NSURL]),
            showsConfirmation: showsConfirmation,
            confirmationScreen: confirmationScreen
        )
    }

    /// Shows a brief status pill for outcomes that have no window of their own
    /// to report in (e.g. a capture that found nothing to copy).
    static func showStatus(_ message: String, systemImage: String, on screen: NSScreen? = nil) {
        Task { @MainActor in
            CopyConfirmationHUD.shared.show(message: message, systemImage: systemImage, on: screen)
        }
    }

    private static func finishCopy(
        _ succeeded: Bool,
        showsConfirmation: Bool,
        confirmationScreen: NSScreen?
    ) -> Bool {
        guard succeeded, showsConfirmation else { return succeeded }
        Task { @MainActor in
            CopyConfirmationHUD.shared.show(on: confirmationScreen)
        }
        return true
    }
}

@MainActor
private final class CopyConfirmationHUD {
    static let shared = CopyConfirmationHUD()
    private static let minimumPanelSize = NSSize(width: 132, height: 58)

    private var panel: NSPanel?
    private var dismissalTask: Task<Void, Never>?

    func show(
        message: String = "Copied",
        systemImage: String = "checkmark.circle.fill",
        on sourceScreen: NSScreen?
    ) {
        dismissalTask?.cancel()

        let panel = panel ?? makePanel()
        let hostingView = NSHostingView(
            rootView: CopyConfirmationHUDView(message: message, systemImage: systemImage)
        )
        // The panel is sized explicitly from the message (with room for the
        // shadow), so the hosting view must not also impose the capsule's own
        // size limits on the window.
        hostingView.sizingOptions = []
        hostingView.frame = NSRect(origin: .zero, size: panelSize(for: message))
        panel.setContentSize(hostingView.frame.size)
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

        position(panel, on: sourceScreen)
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

    /// Wide enough for the capsule (icon, message, padding) plus room for its
    /// shadow; the capsule is centred in whatever is left over.
    private func panelSize(for message: String) -> NSSize {
        let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let textWidth = (message as NSString).size(withAttributes: [.font: font]).width
        return NSSize(
            width: max(Self.minimumPanelSize.width, ceil(textWidth) + 92),
            height: Self.minimumPanelSize.height
        )
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.minimumPanelSize),
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

    private func position(_ panel: NSPanel, on sourceScreen: NSScreen?) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = sourceScreen
            ?? NSApp.keyWindow?.screen
            ?? NSScreen.screens.first { $0.frame.contains(mouseLocation) }
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
    let message: String
    let systemImage: String

    @State private var isVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(message: String, systemImage: String) {
        self.message = message
        self.systemImage = systemImage
    }

    var body: some View {
        Label(message, systemImage: systemImage)
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)
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
