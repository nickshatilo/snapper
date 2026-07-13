import SwiftUI

struct AnnotationEditorView: View {
    @State var canvasState: CanvasState
    @State var toolManager: ToolManager
    @State private var isCopyConfirmationVisible = false
    @State private var copyConfirmationTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            // Top tool options bar
            HStack(spacing: 10) {
                ToolOptionsView(canvasState: canvasState, toolManager: toolManager)

                if canvasState.isOCRProcessing {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                    Text("Reading text...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if toolManager.currentTool == .ocr {
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
                    .zIndex(2)

                Divider()
                    .zIndex(2)

                // Canvas
                ZStack {
                    CanvasView(
                        canvasState: canvasState,
                        toolManager: toolManager,
                        onCopySucceeded: showCopyConfirmation
                    )
                }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .clipped()
                    .zIndex(1)
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
        .overlay {
            if isCopyConfirmationVisible {
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
                    .transition(copyConfirmationTransition)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .onDisappear {
            copyConfirmationTask?.cancel()
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
        guard !isTextInputActive() else {
            return .ignored
        }

        // Tool shortcuts
        if keyPress.modifiers.isEmpty {
            switch keyPress.characters.lowercased() {
            case "v": toolManager.currentTool = .textSelect; return .handled
            case "o": toolManager.currentTool = .ocr; return .handled
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
            let characters = keyPress.characters.lowercased()

            if characters == "c", !keyPress.modifiers.contains(.shift) {
                exportToClipboard()
                return .handled
            }

            if characters == "s" {
                if keyPress.modifiers.contains(.shift) {
                    exportSaveAs()
                } else {
                    exportSave()
                }
                return .handled
            }

            if characters == "z" {
                if keyPress.modifiers.contains(.shift) {
                    canvasState.undoManager.redo(state: canvasState)
                } else {
                    canvasState.undoManager.undo(state: canvasState)
                }
                return .handled
            }

            if characters == "u" {
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

    private func isTextInputActive() -> Bool {
        guard let keyWindow = NSApp.keyWindow,
              let firstResponder = keyWindow.firstResponder else {
            return false
        }

        if firstResponder is NSTextView {
            return true
        }

        if let view = firstResponder as? NSView {
            return view is NSTextField || view is NSSearchField
        }

        return false
    }

    private func exportToClipboard() {
        guard let image = canvasState.renderFinalImage(),
              PasteboardHelper.copyImage(image) else { return }
        showCopyConfirmation()
    }

    private var copyConfirmationTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .scale(scale: 0.84).combined(with: .opacity)
    }

    private func showCopyConfirmation() {
        copyConfirmationTask?.cancel()

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isCopyConfirmationVisible = false
        }

        copyConfirmationTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }

            withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.24, dampingFraction: 0.72)) {
                isCopyConfirmationVisible = true
            }

            do {
                try await Task.sleep(for: .milliseconds(1_100))
            } catch {
                return
            }

            withAnimation(.easeOut(duration: 0.18)) {
                isCopyConfirmationVisible = false
            }
        }
    }

    private func exportSave() {
        guard let image = canvasState.renderFinalImage(),
              let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first else {
            return
        }
        // FileNameGenerator sanitizes path-hostile characters; a raw formatted
        // date contains "/" in most locales, which turns the filename into a
        // nonexistent directory path and makes the save silently fail.
        let filename = FileNameGenerator.generate(
            pattern: "Snapper Annotated {date} at {time}",
            mode: .area
        )
        let url = FileManager.default.uniqueURL(
            for: desktop.appendingPathComponent(filename).appendingPathExtension("png")
        )
        saveOrAlert(image, to: url, format: .png)
    }

    private func exportSaveAs() {
        guard let image = canvasState.renderFinalImage() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff]
        panel.nameFieldStringValue = "Annotated Screenshot.png"
        if panel.runModal() == .OK, let url = panel.url {
            let ext = url.pathExtension.lowercased()
            let format: ImageFormat = ext == "jpg" || ext == "jpeg" ? .jpeg : ext == "tiff" ? .tiff : .png
            saveOrAlert(image, to: url, format: format)
        }
    }

    private func saveOrAlert(_ image: CGImage, to url: URL, format: ImageFormat) {
        guard !ImageUtils.save(image, to: url, format: format) else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Save Failed"
        alert.informativeText = "Couldn't save the image to \(url.path)."
        alert.runModal()
    }

}
