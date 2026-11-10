import AppKit

final class OCRCaptureController {
    private var areaSelectorController: AreaSelectorWindowController?
    private let captureService = ScreenCaptureService()
    private var observerTokens: [NSObjectProtocol] = []

    init() {
        let token = NotificationCenter.default.addObserver(
            forName: .startOCRCapture,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let options = notification.object as? CaptureOptions
            self?.start(options: options)
        }
        observerTokens.append(token)
    }

    deinit {
        for token in observerTokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    func start(options: CaptureOptions? = nil) {
        areaSelectorController?.close()
        areaSelectorController = nil
        areaSelectorController = AreaSelectorWindowController { [weak self] selection in
            guard let self else { return }
            self.areaSelectorController?.close()
            self.areaSelectorController = nil

            guard let selection else {
                // The selector hands focus back itself when it is cancelled.
                NotificationCenter.default.post(name: .ocrCaptureDidFinish, object: nil)
                return
            }
            let rect = selection.rect
            // Convert on the main thread; the task below runs off it.
            let cgRect = CoordinateSpace.appKitToCG(rect)

            Task {
                let image: CGImage
                do {
                    if let frozenImage = selection.frozenImage {
                        image = frozenImage
                    } else {
                        image = try await self.captureService.captureRect(
                            cgRect,
                            retinaScale: options?.retina2x ?? true
                        )
                    }
                } catch {
                    await MainActor.run {
                        NotificationCenter.default.post(name: .ocrCaptureDidFinish, object: nil)
                    }
                    if let captureError = error as? CaptureError, captureError == .permissionDenied {
                        await MainActor.run {
                            PermissionChecker.promptForScreenRecordingInSettings()
                        }
                        return
                    }
                    print("OCR capture failed: \(error)")
                    await MainActor.run {
                        selection.focusRestorer?.restore()
                        CaptureFailureAlert.presentCaptureFailure(error, context: "OCR capture")
                    }
                    return
                }

                // Nothing of Snapper's opens for an OCR capture, and recognition
                // can take a moment, so hand focus back before it starts.
                await MainActor.run {
                    selection.focusRestorer?.restore()
                }

                let recognized = try? await TextRecognitionService.recognizeText(in: image)
                let text = recognized?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                await MainActor.run {
                    let center = CGPoint(x: rect.midX, y: rect.midY)
                    let screen = NSScreen.screens.first { $0.frame.contains(center) }
                    if text.isEmpty {
                        PasteboardHelper.showStatus("No text found", systemImage: "text.viewfinder", on: screen)
                    } else {
                        PasteboardHelper.copyText(text, showsConfirmation: true, confirmationScreen: screen)
                    }
                    NotificationCenter.default.post(name: .ocrCaptureDidFinish, object: nil)
                }
            }
        }
        areaSelectorController?.show(
            freezeScreen: options?.freezeScreen ?? false,
            showMagnifier: options?.showMagnifier ?? false,
            retinaScale: options?.retina2x ?? true
        )
    }
}
