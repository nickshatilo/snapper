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
                NotificationCenter.default.post(name: .ocrCaptureDidFinish, object: nil)
                return
            }
            let rect = selection.rect
            // Convert on the main thread; the task below runs off it.
            let cgRect = CoordinateSpace.appKitToCG(rect)

            Task {
                do {
                    let image: CGImage
                    if let frozenImage = selection.frozenImage {
                        image = frozenImage
                    } else {
                        image = try await self.captureService.captureRect(
                            cgRect,
                            retinaScale: options?.retina2x ?? true
                        )
                    }
                    await MainActor.run {
                        AnnotationEditorWindow.open(with: image)
                        NotificationCenter.default.post(name: .ocrCaptureDidFinish, object: nil)
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
                    // No editor opened, so hand focus back to the user's app.
                    await MainActor.run {
                        selection.focusRestorer?.restore()
                    }
                    print("OCR capture failed: \(error)")
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
