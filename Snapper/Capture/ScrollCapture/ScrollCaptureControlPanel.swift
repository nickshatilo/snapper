import AppKit
import SwiftUI

final class ScrollCaptureControlState: ObservableObject {
    @Published var statusText: String = "Preparing scroll capture..."
}

struct ScrollCaptureControlPanelView: View {
    @ObservedObject var state: ScrollCaptureControlState
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)

            Text(state.statusText)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Button("Stop", action: onStop)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help("Stop and keep what has been captured. Press Esc to cancel.")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

@MainActor
final class ScrollCaptureControlPanel {
    let state = ScrollCaptureControlState()
    private let onStop: () -> Void
    private let onCancel: () -> Void
    private var panel: NSPanel?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?

    init(onStop: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.onStop = onStop
        self.onCancel = onCancel
    }

    /// Shows the panel on the screen containing `captureRect` (AppKit global
    /// coordinates), placed so it doesn't overlap the region being captured.
    func show(near captureRect: CGRect) {
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            return
        }

        let screen = NSScreen.screens.first(where: { $0.frame.intersects(captureRect) }) ?? NSScreen.main
        guard let screen else { return }
        let hostingView = NSHostingView(
            rootView: ScrollCaptureControlPanelView(
                state: state,
                onStop: onStop
            )
        )

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 54),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Keep the panel out of screen captures entirely.
        panel.sharingType = .none
        panel.contentView = hostingView

        var origin = NSPoint(
            x: screen.frame.midX - (panel.frame.width / 2),
            y: screen.visibleFrame.maxY - panel.frame.height - 56
        )
        if captureRect.intersects(CGRect(origin: origin, size: panel.frame.size)) {
            origin.y = screen.visibleFrame.minY + 56
        }
        panel.setFrameOrigin(origin)

        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
        installEscapeMonitors()
    }

    func close() {
        removeEscapeMonitors()
        panel?.orderOut(nil)
        panel = nil
    }

    /// Escape cancels the session. The scrolled app is frontmost, so this
    /// needs a global monitor (delivered only when Snapper is trusted for
    /// Accessibility); the local one covers Snapper itself being active.
    private func installEscapeMonitors() {
        removeEscapeMonitors()
        let escapeKeyCode: UInt16 = 53
        let onCancel = onCancel
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == escapeKeyCode {
                onCancel()
            }
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == escapeKeyCode else { return event }
            onCancel()
            return nil
        }
    }

    private func removeEscapeMonitors() {
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
            self.globalKeyMonitor = nil
        }
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
    }
}
