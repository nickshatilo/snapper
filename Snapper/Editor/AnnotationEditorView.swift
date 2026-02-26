import SwiftUI

struct AnnotationEditorView: View {
    @State var canvasState: CanvasState
    @State var toolManager: ToolManager

    var body: some View {
        VStack(spacing: 0) {
            // Top tool options bar
            HStack(spacing: 10) {
                ToolOptionsView(toolManager: toolManager)

                if canvasState.isOCRProcessing {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                    Text("Reading text...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if toolManager.currentTool == .textSelect {
                    Spacer()
                    Text(
                        canvasState.recognizedTextRegionCount > 0
                            ? "Detected \(canvasState.recognizedTextRegionCount) text regions"
                            : "No text detected"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .frame(height: 44)
            .padding(.trailing, 10)
            .background(.bar)

            Divider()

            HStack(spacing: 0) {
                // Left toolbar
                ToolbarView(toolManager: toolManager)
                    .frame(width: 44)
                    .background(.bar)

                Divider()

                // Canvas
                CanvasView(canvasState: canvasState, toolManager: toolManager)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }

            Divider()

            // Bottom status bar
            statusBar
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .focusable()
        .onKeyPress { keyPress in
            handleKeyPress(keyPress)
        }
    }

    private var statusBar: some View {
        HStack {
            Text("\(canvasState.imageWidth) × \(canvasState.imageHeight)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Text("Zoom: \(Int(canvasState.zoomLevel * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            HStack(spacing: 8) {
                Button(action: { canvasState.undoManager.undo(state: canvasState) }) {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(!canvasState.undoManager.canUndo)
                .help("Undo (⌘Z)")

                Button(action: { canvasState.undoManager.redo(state: canvasState) }) {
                    Image(systemName: "arrow.uturn.forward")
                }
                .disabled(!canvasState.undoManager.canRedo)
                .help("Redo (⌘⇧Z)")
            }

            Spacer()

            Menu("Export") {
                Button("Copy to Clipboard ⌘C") { exportToClipboard() }
                Button("Save ⌘S") { exportSave() }
                Button("Save As... ⌘⇧S") { exportSaveAs() }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private func handleKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        // Tool shortcuts
        if keyPress.modifiers.isEmpty {
            switch keyPress.characters.lowercased() {
            case "v": toolManager.currentTool = .textSelect; return .handled
            case "m": toolManager.currentTool = .hand; return .handled
            case "a": toolManager.currentTool = .arrow; return .handled
            case "r": toolManager.currentTool = .rectangle; return .handled
            case "e": toolManager.currentTool = .ellipse; return .handled
            case "l": toolManager.currentTool = .line; return .handled
            case "p": toolManager.currentTool = .pencil; return .handled
            case "h": toolManager.currentTool = .highlighter; return .handled
            case "t": toolManager.currentTool = .text; return .handled
            case "b": toolManager.currentTool = .blur; return .handled
            case "x": toolManager.currentTool = .pixelate; return .handled
            case "s": toolManager.currentTool = .spotlight; return .handled
            case "n": toolManager.currentTool = .counter; return .handled
            case "c": toolManager.currentTool = .crop; return .handled
            default: break
            }
        }

        if keyPress.modifiers.contains(.command) {
            if keyPress.characters == "z" {
                if keyPress.modifiers.contains(.shift) {
                    canvasState.undoManager.redo(state: canvasState)
                } else {
                    canvasState.undoManager.undo(state: canvasState)
                }
                return .handled
            }

            if keyPress.characters == "u" {
                if keyPress.modifiers.contains(.shift) {
                    canvasState.undoManager.redo(state: canvasState)
                } else {
                    canvasState.undoManager.undo(state: canvasState)
                }
                return .handled
            }
        }

        return .ignored
    }

    private func exportToClipboard() {
        if let image = canvasState.renderFinalImage() {
            PasteboardHelper.copyImage(image)
        }
    }

    private func exportSave() {
        guard let image = canvasState.renderFinalImage() else { return }
        let url = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Snapper Annotated \(Date().formatted(date: .numeric, time: .shortened)).png")
        _ = ImageUtils.save(image, to: url, format: .png)
    }

    private func exportSaveAs() {
        guard let image = canvasState.renderFinalImage() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff]
        panel.nameFieldStringValue = "Annotated Screenshot.png"
        if panel.runModal() == .OK, let url = panel.url {
            let ext = url.pathExtension.lowercased()
            let format: ImageFormat = ext == "jpg" || ext == "jpeg" ? .jpeg : ext == "tiff" ? .tiff : .png
            _ = ImageUtils.save(image, to: url, format: format)
        }
    }

}
