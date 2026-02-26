import AppKit

final class OCRCaptureController {
    private var areaSelectorController: AreaSelectorWindowController?
    private let captureService = ScreenCaptureService()

    init() {
        NotificationCenter.default.addObserver(
            forName: .startOCRCapture,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.start()
        }
    }

    func start() {
        areaSelectorController = AreaSelectorWindowController { [weak self] rect in
            guard let self else { return }
            self.areaSelectorController?.close()
            self.areaSelectorController = nil

            guard let rect else { return }

            Task {
                do {
                    let image = try await self.captureService.captureRect(rect)
                    await MainActor.run {
                        AnnotationEditorWindow.open(with: image)
                    }
                } catch {
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
        areaSelectorController?.show(freezeScreen: false)
    }
}
