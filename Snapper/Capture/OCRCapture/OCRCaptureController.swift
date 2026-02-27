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
        areaSelectorController = AreaSelectorWindowController { [weak self] rect in
            guard let self else { return }
            self.areaSelectorController?.close()
            self.areaSelectorController = nil

            guard let rect else {
                NotificationCenter.default.post(name: .ocrCaptureDidFinish, object: nil)
                return
            }

            Task {
                do {
                    let image = try await self.captureService.captureRect(
                        rect,
                        retinaScale: options?.retina2x ?? true
                    )
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
                    print("OCR capture failed: \(error)")
                }
            }
        }
        areaSelectorController?.show(
            freezeScreen: options?.freezeScreen ?? false,
            showMagnifier: options?.showMagnifier ?? false
        )
    }
}
