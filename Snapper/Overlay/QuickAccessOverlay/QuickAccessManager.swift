import AppKit
import QuartzCore
import SwiftUI

@Observable
final class QuickAccessManager {
    var captures: [QuickAccessCapture] = []
    private var panel: QuickAccessPanel?
    private let appState: AppState
    @ObservationIgnored private var observerTokens: [NSObjectProtocol] = []
    private let thumbnailWidth: CGFloat = 240
    private let thumbnailMaxHeight: CGFloat = 170
    private let thumbnailHorizontalInset: CGFloat = 8
    private let thumbnailVerticalInset: CGFloat = 4
    private let panelMaxHeight: CGFloat = 560
    private let panelMinHeight: CGFloat = 120
    private let maxCaptures = 20

    init(appState: AppState) {
        self.appState = appState
        observeCaptures()
        observeLayoutChanges()
    }

    deinit {
        for token in observerTokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    private func observeCaptures() {
        let token = NotificationCenter.default.addObserver(
            forName: .captureCompleted,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let info = notification.object as? CaptureCompletedInfo else { return }
            self?.addCapture(info)
        }
        observerTokens.append(token)
    }

    private func observeLayoutChanges() {
        let cornerToken = NotificationCenter.default.addObserver(
            forName: .overlayCornerChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updatePanelLayout(animated: true)
        }
        observerTokens.append(cornerToken)

        let screenToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updatePanelLayout(animated: true)
        }
        observerTokens.append(screenToken)
    }

    func addCapture(_ info: CaptureCompletedInfo) {
        let thumbnail = info.thumbnail ?? info.result.image
        let capture = QuickAccessCapture(
            id: UUID(),
            recordID: info.recordID,
            inMemoryImage: info.savedURL == nil ? info.result.image : nil,
            thumbnail: thumbnail,
            mode: info.result.mode,
            timestamp: info.result.timestamp,
            savedURL: info.savedURL,
            width: info.result.width,
            height: info.result.height,
            fileSize: info.fileSize
        )
        withAnimation(.interactiveSpring(response: 0.4, dampingFraction: 0.86, blendDuration: 0.12)) {
            captures.insert(capture, at: 0)
            if captures.count > maxCaptures {
                captures.removeLast(captures.count - maxCaptures)
            }
        }
        showPanel()
    }

    func removeCapture(_ id: UUID) {
        withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.9, blendDuration: 0.08)) {
            captures.removeAll { $0.id == id }
        }
        if captures.isEmpty {
            hidePanel()
        } else {
            updatePanelLayout(animated: true)
        }
    }

    func dismissAll() {
        withAnimation(.easeInOut(duration: 0.2)) {
            captures.removeAll()
        }
        hidePanel()
    }

    private func showPanel() {
        if panel == nil {
            let panel = QuickAccessPanel(
                contentRect: NSRect(x: 0, y: 0, width: thumbnailWidth, height: panelMinHeight),
                styleMask: [],
                backing: .buffered,
                defer: true
            )

            let contentView = QuickAccessOverlayView(manager: self, thumbnailWidth: thumbnailWidth)
            let hostingView = NSHostingView(rootView: contentView)
            panel.contentView = hostingView
            self.panel = panel
        }

        let shouldAnimate = panel?.isVisible == true
        updatePanelLayout(animated: shouldAnimate)
        panel?.orderFront(nil)
    }

    private func hidePanel() {
        panel?.orderOut(nil)
        panel = nil
    }

    private func updatePanelLayout(animated: Bool) {
        guard let panel else { return }
        let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }

        let margin: CGFloat = 16
        let screenFrame = screen.visibleFrame
        let targetSize = NSSize(width: thumbnailWidth, height: targetPanelHeight())

        let origin: NSPoint
        switch appState.overlayCorner {
        case .topLeft:
            origin = NSPoint(
                x: screenFrame.minX + margin,
                y: screenFrame.maxY - targetSize.height - margin
            )
        case .topRight:
            origin = NSPoint(
                x: screenFrame.maxX - targetSize.width - margin,
                y: screenFrame.maxY - targetSize.height - margin
            )
        case .bottomLeft:
            origin = NSPoint(
                x: screenFrame.minX + margin,
                y: screenFrame.minY + margin
            )
        case .bottomRight:
            origin = NSPoint(
                x: screenFrame.maxX - targetSize.width - margin,
                y: screenFrame.minY + margin
            )
        }

        let targetFrame = NSRect(origin: origin, size: targetSize)
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.24
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(targetFrame, display: true)
            }
        } else {
            panel.setFrame(targetFrame, display: true)
        }
    }

    private func targetPanelHeight() -> CGFloat {
        let spacing: CGFloat = 8
        let padding: CGFloat = 16
        let captureHeights = captures.reduce(CGFloat.zero) { partial, capture in
            partial + estimatedThumbnailHeight(for: capture)
        }
        let contentHeight = captureHeights + max(0, CGFloat(captures.count - 1)) * spacing + padding
        return min(panelMaxHeight, max(panelMinHeight, contentHeight))
    }

    private func estimatedThumbnailHeight(for capture: QuickAccessCapture) -> CGFloat {
        let width = max(1, thumbnailWidth - thumbnailHorizontalInset)
        let ratio = CGFloat(capture.height) / max(1, CGFloat(capture.width))
        let rawHeight = width * ratio
        let imageHeight = min(thumbnailMaxHeight, max(56, rawHeight))
        return imageHeight + thumbnailVerticalInset
    }
}

struct QuickAccessCapture: Identifiable {
    let id: UUID
    let recordID: UUID
    let inMemoryImage: CGImage?
    let thumbnail: CGImage
    let mode: CaptureMode
    let timestamp: Date
    let savedURL: URL?
    let width: Int
    let height: Int
    let fileSize: Int

    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
    }

    func resolvedImage() -> CGImage? {
        if let inMemoryImage {
            return inMemoryImage
        }

        guard let savedURL else { return nil }
        let cacheKey = savedURL.path as NSString
        if let cachedImage = Self.loadedImageCache.object(forKey: cacheKey),
           let cachedCG = cachedImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return cachedCG
        }

        guard let nsImage = NSImage(contentsOf: savedURL),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        Self.loadedImageCache.setObject(nsImage, forKey: cacheKey)
        return cgImage
    }

    private static let loadedImageCache = NSCache<NSString, NSImage>()
}
