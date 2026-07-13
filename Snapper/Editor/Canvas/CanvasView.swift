import SwiftUI

struct CanvasView: NSViewRepresentable {
    let canvasState: CanvasState
    let toolManager: ToolManager

    func makeNSView(context: Context) -> CanvasNSView {
        let view = CanvasNSView(canvasState: canvasState, toolManager: toolManager)
        return view
    }

    func updateNSView(_ nsView: CanvasNSView, context: Context) {
        nsView.canvasState = canvasState
        nsView.toolManager = toolManager
        nsView.needsDisplay = true
    }
}
