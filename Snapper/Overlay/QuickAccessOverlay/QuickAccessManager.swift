import AppKit
import SwiftUI

@Observable
final class QuickAccessManager {
    var captures: [QuickAccessCapture] = []
    private var panel: QuickAccessPanel?
    private let appState: AppState
    private var observerTokens: [NSObjectProtocol] = []
    private let thumbnailWidth: CGFloat = 240
    private let thumbnailApproxHeight: CGFloat = 150
    private let panelMaxHeight: CGFloat = 560

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
            self?.positionPanel()
        }
        observerTokens.append(cornerToken)

        let screenToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.positionPanel()
        }
        observerTokens.append(screenToken)
    }

    func addCapture(_ info: CaptureCompletedInfo) {
        let thumbnail = ImageUtils.generateThumbnail(info.result.image)
        let capture = QuickAccessCapture(
            id: UUID(),
            image: info.result.image,
            thumbnail: thumbnail ?? info.result.image,
            mode: info.result.mode,
            timestamp: info.result.timestamp,
            savedURL: info.savedURL,
            width: info.result.width,
            height: info.result.height,
            fileSize: info.savedURL.flatMap { try? FileManager.default.attributesOfItem(atPath: $0.path)[.size] as? Int } ?? 0
        )
        captures.insert(capture, at: 0)
        showPanel()
    }

    func removeCapture(_ id: UUID) {
        captures.removeAll { $0.id == id }
        if captures.isEmpty {
            hidePanel()
        }
    }

    func dismissAll() {
        captures.removeAll()
        hidePanel()
    }

    private func showPanel() {
        if panel == nil {
            let panel = QuickAccessPanel(
                contentRect: NSRect(x: 0, y: 0, width: thumbnailWidth, height: thumbnailApproxHeight),
                styleMask: [],
                backing: .buffered,
                defer: true
            )

            let contentView = QuickAccessOverlayView(manager: self, thumbnailWidth: thumbnailWidth)
            let hostingView = NSHostingView(rootView: contentView)
            panel.contentView = hostingView
            self.panel = panel
        }

        updatePanelSize()
        positionPanel()
        panel?.orderFront(nil)
    }

    private func hidePanel() {
        panel?.orderOut(nil)
    }

    private func positionPanel() {
        guard let panel, let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let margin: CGFloat = 16
        let screenFrame = screen.visibleFrame

        let origin: NSPoint
        switch appState.overlayCorner {
        case .topLeft:
            origin = NSPoint(
                x: screenFrame.minX + margin,
                y: screenFrame.maxY - panel.frame.height - margin
            )
        case .topRight:
            origin = NSPoint(
                x: screenFrame.maxX - panel.frame.width - margin,
                y: screenFrame.maxY - panel.frame.height - margin
            )
        case .bottomLeft:
            origin = NSPoint(
                x: screenFrame.minX + margin,
                y: screenFrame.minY + margin
            )
        case .bottomRight:
            origin = NSPoint(
                x: screenFrame.maxX - panel.frame.width - margin,
                y: screenFrame.minY + margin
            )
        }
        panel.setFrameOrigin(origin)
    }

    private func updatePanelSize() {
        guard let panel else { return }
        let captureCount = CGFloat(captures.count)
        let spacing: CGFloat = 8
        let padding: CGFloat = 16
        let contentHeight = captureCount * thumbnailApproxHeight + max(0, captureCount - 1) * spacing + padding
        let height = min(panelMaxHeight, max(thumbnailApproxHeight, contentHeight))
        panel.setContentSize(NSSize(width: thumbnailWidth, height: height))
    }
}

struct QuickAccessCapture: Identifiable {
    let id: UUID
    let image: CGImage
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
}
