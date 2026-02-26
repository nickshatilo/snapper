import AppKit

@Observable
final class CaptureCoordinator {
    private let appState: AppState
    private let captureService = ScreenCaptureService()
    private var areaSelectorController: AreaSelectorWindowController?
    private var windowSelectorController: WindowSelectorController?

    init(appState: AppState) {
        self.appState = appState
        observeCaptureTriggers()
    }

    private func observeCaptureTriggers() {
        NotificationCenter.default.addObserver(
            forName: .startCapture,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let mode = notification.object as? CaptureMode else { return }
            self?.startCapture(mode: mode)
        }
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
        case .scrolling:
            NotificationCenter.default.post(name: .startScrollingCapture, object: options)
            appState.isCapturing = false
        case .ocr:
            NotificationCenter.default.post(name: .startOCRCapture, object: options)
            appState.isCapturing = false
        case .timer:
            NotificationCenter.default.post(name: .startTimerCapture, object: TimerCaptureRequest.default)
            appState.isCapturing = false
        }
    }

    private func captureFullscreen(options: CaptureOptions) {
        Task {
            do {
                let image = try await captureService.captureDisplay()
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
                    let image = try await self.captureService.captureRect(rect)
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
        areaSelectorController?.show(freezeScreen: options.freezeScreen)
    }

    private func captureWindow(options: CaptureOptions) {
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
                    let image = try await self.captureService.captureWindow(windowInfo.window)
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

        DispatchQueue.global(qos: .userInitiated).async {
            var savedURL: URL?
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
                }
            }

            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .captureCompleted,
                    object: CaptureCompletedInfo(result: result, savedURL: savedURL)
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
    let result: CaptureResult
    let savedURL: URL?
}

extension Notification.Name {
    static let showAllInOneHUD = Notification.Name("showAllInOneHUD")
    static let startScrollingCapture = Notification.Name("startScrollingCapture")
    static let startOCRCapture = Notification.Name("startOCRCapture")
    static let startTimerCapture = Notification.Name("startTimerCapture")
}
