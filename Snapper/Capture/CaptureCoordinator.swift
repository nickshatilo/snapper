import AppKit

@Observable
final class CaptureCoordinator {
    private let appState: AppState
    private let captureService = ScreenCaptureService()
    private var areaSelectorController: AreaSelectorWindowController?
    private var windowSelectorController: WindowSelectorController?
    private var observerTokens: [NSObjectProtocol] = []

    init(appState: AppState) {
        self.appState = appState
        observeCaptureTriggers()
    }

    deinit {
        for token in observerTokens {
            NotificationCenter.default.removeObserver(token)
        }
    }

    private func observeCaptureTriggers() {
        let token = NotificationCenter.default.addObserver(
            forName: .startCapture,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let mode = notification.object as? CaptureMode else { return }
            self?.startCapture(mode: mode)
        }
        observerTokens.append(token)

        let ocrFinishToken = NotificationCenter.default.addObserver(
            forName: .ocrCaptureDidFinish,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.appState.isCapturing = false
        }
        observerTokens.append(ocrFinishToken)

        let timerFinishToken = NotificationCenter.default.addObserver(
            forName: .timerCaptureDidFinish,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.appState.isCapturing = false
        }
        observerTokens.append(timerFinishToken)
    }

    func startCapture(mode: CaptureMode) {
        guard !appState.isCapturing else { return }
        appState.isCapturing = true

        let options = CaptureOptions.from(appState: appState)

        switch mode {
        case .fullscreen:
            captureFullscreen(options: options)
        case .area:
            captureArea(options: options)
        case .window:
            captureWindow(options: options)
        case .ocr:
            NotificationCenter.default.post(name: .startOCRCapture, object: options)
        case .timer:
            NotificationCenter.default.post(name: .startTimerCapture, object: TimerCaptureRequest.default)
        }
    }

    private func captureFullscreen(options: CaptureOptions) {
        Task {
            do {
                let image = try await captureService.captureDisplay(retinaScale: options.retina2x)
                let result = CaptureResult(
                    image: image,
                    mode: .fullscreen,
                    timestamp: Date(),
                    sourceRect: NSScreen.main?.frame ?? .zero,
                    windowName: nil,
                    applicationName: nil
                )
                await finishCapture(result: result, options: options)
            } catch {
                await handleCaptureError(error, context: "Fullscreen capture")
            }
        }
    }

    private func captureArea(options: CaptureOptions) {
        areaSelectorController?.close()
        areaSelectorController = nil
        areaSelectorController = AreaSelectorWindowController { [weak self] rect in
            guard let self else { return }
            self.areaSelectorController?.close()
            self.areaSelectorController = nil

            guard let rect else {
                self.appState.isCapturing = false
                return
            }

            Task {
                do {
                    let image = try await self.captureService.captureRect(rect, retinaScale: options.retina2x)
                    let result = CaptureResult(
                        image: image,
                        mode: .area,
                        timestamp: Date(),
                        sourceRect: rect,
                        windowName: nil,
                        applicationName: nil
                    )
                    await self.finishCapture(result: result, options: options)
                } catch {
                    await self.handleCaptureError(error, context: "Area capture")
                }
            }
        }
        areaSelectorController?.show(freezeScreen: options.freezeScreen, showMagnifier: options.showMagnifier)
    }

    private func captureWindow(options: CaptureOptions) {
        windowSelectorController?.close()
        windowSelectorController = nil
        windowSelectorController = WindowSelectorController { [weak self] windowInfo in
            guard let self else { return }
            self.windowSelectorController?.close()
            self.windowSelectorController = nil

            guard let windowInfo else {
                self.appState.isCapturing = false
                return
            }

            Task {
                do {
                    let image = try await self.captureService.captureWindow(
                        windowInfo.window,
                        retinaScale: options.retina2x,
                        includeShadow: options.includeShadow
                    )
                    let result = CaptureResult(
                        image: image,
                        mode: .window,
                        timestamp: Date(),
                        sourceRect: windowInfo.frame,
                        windowName: windowInfo.title,
                        applicationName: windowInfo.appName
                    )
                    await self.finishCapture(result: result, options: options)
                } catch {
                    await self.handleCaptureError(error, context: "Window capture")
                }
            }
        }
        windowSelectorController?.show()
    }

    @MainActor
    func finishCapture(result: CaptureResult, options: CaptureOptions) {
        appState.isCapturing = false

        // Copy to clipboard
        if options.copyToClipboard {
            PasteboardHelper.copyImage(result.image)
        }

        // Play sound
        if options.playSound {
            SoundPlayer.playCapture(options.captureSound)
        }

        let recordID = UUID()
        DispatchQueue.global(qos: .userInitiated).async {
            var savedURL: URL?
            var fileSize = 0
            if options.saveToFile {
                let filename = FileNameGenerator.generate(
                    pattern: options.filenamePattern,
                    mode: result.mode,
                    appName: result.applicationName
                )
                let url = options.saveDirectory
                    .appendingPathComponent(filename)
                    .appendingPathExtension(options.format.fileExtension)
                if ImageUtils.save(result.image, to: url, format: options.format, jpegQuality: options.jpegQuality) {
                    savedURL = url
                    fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
                }
            }
            let thumbnail = ImageUtils.generateThumbnail(result.image)

            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .captureCompleted,
                    object: CaptureCompletedInfo(
                        recordID: recordID,
                        result: result,
                        savedURL: savedURL,
                        fileSize: fileSize,
                        thumbnail: thumbnail
                    )
                )
            }
        }
    }

    @MainActor
    private func handleCaptureError(_ error: Error, context: String) {
        appState.isCapturing = false

        if let captureError = error as? CaptureError, captureError == .permissionDenied {
            PermissionChecker.promptForScreenRecordingInSettings()
            return
        }

        print("\(context) failed: \(error)")
    }
}

struct CaptureCompletedInfo {
    let recordID: UUID
    let result: CaptureResult
    let savedURL: URL?
    let fileSize: Int
    let thumbnail: CGImage?
}

extension Notification.Name {
    static let showAllInOneHUD = Notification.Name("showAllInOneHUD")
    static let startOCRCapture = Notification.Name("startOCRCapture")
    static let startTimerCapture = Notification.Name("startTimerCapture")
    static let deleteHistoryRecord = Notification.Name("deleteHistoryRecord")
    static let ocrCaptureDidFinish = Notification.Name("ocrCaptureDidFinish")
    static let timerCaptureDidFinish = Notification.Name("timerCaptureDidFinish")
}
