import SwiftUI

struct CanvasView: NSViewRepresentable {
    let canvasState: CanvasState
    let toolManager: ToolManager
    let onCopySucceeded: () -> Void

    func makeNSView(context: Context) -> CanvasNSView {
        let view = CanvasNSView(
            canvasState: canvasState,
            toolManager: toolManager,
            onCopySucceeded: onCopySucceeded
        )
        return view
    }

    func updateNSView(_ nsView: CanvasNSView, context: Context) {
        nsView.canvasState = canvasState
        nsView.toolManager = toolManager
        nsView.onCopySucceeded = onCopySucceeded
        nsView.needsDisplay = true
    }
}
