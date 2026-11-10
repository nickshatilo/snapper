import AppKit
import UniformTypeIdentifiers

/// Export actions shared by the editor's shortcuts and menu and by the
/// window's save-on-close prompt, so every path renders, names and tracks
/// saved state the same way.
enum EditorExporter {
    /// Expanded through `FileNameGenerator`, which sanitizes path-hostile
    /// characters; a raw formatted date contains "/" in most locales, which
    /// turns the filename into a nonexistent directory path.
    static let annotatedFilenamePattern = "Snapper Annotated {date} at {time}"

    static func format(forPathExtension pathExtension: String) -> ImageFormat {
        switch pathExtension.lowercased() {
        case "jpg", "jpeg": return .jpeg
        case "tif", "tiff": return .tiff
        default: return .png
        }
    }

    @MainActor
    static func copyToClipboard(_ state: CanvasState, screen: NSScreen?) {
        // Commit an in-progress inline text edit so the export matches the screen.
        state.commitPendingEdits()
        guard let image = state.renderFinalImage() else { return }
        let copied = PasteboardHelper.copyImage(
            image,
            scale: state.sourceScale,
            showsConfirmation: true,
            confirmationScreen: screen
        )
        // The annotated image now lives on the clipboard, so closing the
        // editor afterwards shouldn't prompt to save it.
        if copied {
            state.markSaved()
        }
    }

    /// Saves over the file this document was last saved to, or to a new file
    /// in the user's save folder the first time. The original capture file is
    /// never touched. Returns false (after alerting) if nothing was written.
    @MainActor
    @discardableResult
    static func save(_ state: CanvasState, options: CaptureOptions) -> Bool {
        // Commit an in-progress inline text edit so the export matches the screen.
        state.commitPendingEdits()
        guard let image = state.renderFinalImage() else {
            showSaveFailedAlert("Couldn't render the annotated image.")
            return false
        }

        if let existingURL = state.lastSavedURL {
            let existingFormat = format(forPathExtension: existingURL.pathExtension)
            guard write(image, to: existingURL, format: existingFormat, jpegQuality: options.jpegQuality, state: state) else {
                showSaveFailedAlert("Couldn't save the image to \(existingURL.path).")
                return false
            }
            return true
        }

        let filename = FileNameGenerator.generate(pattern: annotatedFilenamePattern, mode: .area)
        let proposedURL = options.saveDirectory
            .appendingPathComponent(filename)
            .appendingPathExtension(options.format.fileExtension)
        // Reserving the name atomically keeps a capture being written to the
        // same folder at the same moment from claiming it too.
        guard let url = FileManager.default.reserveUniqueURL(for: proposedURL) else {
            showSaveFailedAlert("Couldn't save the image to \(proposedURL.path).")
            return false
        }
        guard write(image, to: url, format: options.format, jpegQuality: options.jpegQuality, state: state) else {
            // Don't leave the empty placeholder behind.
            try? FileManager.default.removeItem(at: url)
            showSaveFailedAlert("Couldn't save the image to \(url.path).")
            return false
        }
        return true
    }

    /// Asks where to save; the format follows the chosen extension. Returns
    /// false if the panel was cancelled or the write failed.
    @MainActor
    @discardableResult
    static func saveAs(_ state: CanvasState, jpegQuality: Double = 0.9) -> Bool {
        // Commit an in-progress inline text edit so the export matches the screen.
        state.commitPendingEdits()
        guard let image = state.renderFinalImage() else {
            showSaveFailedAlert("Couldn't render the annotated image.")
            return false
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff]
        panel.nameFieldStringValue = "Annotated Screenshot.png"
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        let chosenFormat = format(forPathExtension: url.pathExtension)
        guard write(image, to: url, format: chosenFormat, jpegQuality: jpegQuality, state: state) else {
            showSaveFailedAlert("Couldn't save the image to \(url.path).")
            return false
        }
        return true
    }

    /// Writes `image` and, on success, makes `url` the document's file.
    @MainActor
    private static func write(
        _ image: CGImage,
        to url: URL,
        format: ImageFormat,
        jpegQuality: Double,
        state: CanvasState
    ) -> Bool {
        guard ImageUtils.save(image, to: url, format: format, jpegQuality: jpegQuality, scale: state.sourceScale) else {
            return false
        }
        state.lastSavedURL = url
        state.markSaved()
        return true
    }

    @MainActor
    private static func showSaveFailedAlert(_ informativeText: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Save Failed"
        alert.informativeText = informativeText
        alert.runModal()
    }
}
