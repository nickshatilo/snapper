import AppKit

final class CaptureCoordinator {
    private let appState: AppState
    private let notificationCenter: NotificationCenter
    private let captureService = ScreenCaptureService()
    private lazy var scrollCaptureCoordinator = ScrollCaptureCoordinator(
        appState: appState,
        finishCapture: { [weak self] result, options in
            Task { @MainActor in
                self?.finishCapture(result: result, options: options)
            }
        },
        handleError: { [weak self] error, context in
            Task { @MainActor in
                self?.handleCaptureError(error, context: context)
            }
        },
        onSessionEnd: { [weak self] in
            Task { @MainActor in
                self?.appState.isCapturing = false
            }
        }
    )
    private var areaSelectorController: AreaSelectorWindowController?
    private var windowSelectorController: WindowSelectorController?
    private var observerTokens: [NSObjectProtocol] = []

    init(appState: AppState, notificationCenter: NotificationCenter = .default) {
        self.appState = appState
        self.notificationCenter = notificationCenter
        observeCaptureTriggers()
    }

    deinit {
        for token in observerTokens {
            notificationCenter.removeObserver(token)
        }
    }

    private func observeCaptureTriggers() {
        let token = notificationCenter.addObserver(
            forName: .startCapture,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let request = notification.object as? TimerCaptureRequest {
                self?.startTimerCapture(request: request)
            } else if let mode = notification.object as? CaptureMode {
                self?.startCapture(mode: mode)
            }
        }
        observerTokens.append(token)

        let ocrFinishToken = notificationCenter.addObserver(
            forName: .ocrCaptureDidFinish,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.appState.isCapturing = false
        }
        observerTokens.append(ocrFinishToken)

        let timerFinishToken = notificationCenter.addObserver(
            forName: .timerCaptureDidFinish,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            if let mode = notification.object as? CaptureMode {
                // The countdown owns the existing capture reservation. Continue
                // directly instead of re-entering startCapture and hitting its guard.
                guard self.appState.isCapturing else { return }
                self.performCapture(mode: mode == .timer ? .fullscreen : mode)
            } else {
                // A nil mode means the countdown was cancelled or could not start.
                self.appState.isCapturing = false
            }
        }
        observerTokens.append(timerFinishToken)
    }

    func startCapture(mode: CaptureMode) {
        guard !appState.isCapturing else { return }
        appState.isCapturing = true

        performCapture(mode: mode)
    }

    private func startTimerCapture(request: TimerCaptureRequest) {
        guard !appState.isCapturing else { return }
        appState.isCapturing = true
        notificationCenter.post(name: .startTimerCapture, object: request)
    }

    private func performCapture(mode: CaptureMode) {
        let options = CaptureOptions.from(appState: appState)

        switch mode {
        case .fullscreen:
            captureFullscreen(options: options)
        case .area:
            captureArea(options: options)
        case .window:
            captureWindow(options: options)
        case .scroll:
            captureScroll(options: options)
        case .ocr:
            notificationCenter.post(name: .startOCRCapture, object: options)
        case .timer:
            notificationCenter.post(name: .startTimerCapture, object: TimerCaptureRequest.default)
        }
    }

    private func captureFullscreen(options: CaptureOptions) {
        Task {
            do {
                let capture = try await captureService.captureAllDisplays(retinaScale: options.retina2x)
                let result = CaptureResult(
                    image: capture.image,
                    mode: .fullscreen,
                    timestamp: Date(),
                    sourceRect: capture.sourceRect,
                    windowName: nil,
                    applicationName: nil,
                    scale: capture.scale
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
        areaSelectorController = AreaSelectorWindowController { [weak self] selection in
            guard let self else { return }
            self.areaSelectorController = nil

            guard let selection else {
                self.appState.isCapturing = false
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
                            retinaScale: options.retina2x
                        )
                    }
                    let result = CaptureResult(
                        image: image,
                        mode: .area,
                        timestamp: Date(),
                        sourceRect: cgRect,
                        windowName: nil,
                        applicationName: nil,
                        scale: rect.width > 0 ? CGFloat(image.width) / rect.width : 1
                    )
                    await self.finishCapture(result: result, options: options)
                    await self.restoreFocus(selection.focusRestorer, after: nil)
                } catch {
                    await self.handleCaptureError(error, context: "Area capture")
                    await self.restoreFocus(selection.focusRestorer, after: error)
                }
            }
        }
        areaSelectorController?.show(
            freezeScreen: options.freezeScreen,
            showMagnifier: options.showMagnifier,
            retinaScale: options.retina2x
        )
    }

    private func captureWindow(options: CaptureOptions) {
        windowSelectorController?.close()
        windowSelectorController = nil
        windowSelectorController = WindowSelectorController(completion: { [weak self] windowInfo in
            guard let self else { return }
            self.windowSelectorController?.close()
            self.windowSelectorController = nil

            guard let windowInfo else {
                self.appState.isCapturing = false
                return
            }

            Task {
                do {
                    let capture = try await self.captureService.captureWindow(
                        windowInfo.window,
                        retinaScale: options.retina2x,
                        includeShadow: options.includeShadow
                    )
                    let result = CaptureResult(
                        image: capture.image,
                        mode: .window,
                        timestamp: Date(),
                        sourceRect: windowInfo.frame,
                        windowName: windowInfo.title,
                        applicationName: windowInfo.appName,
                        scale: capture.scale
                    )
                    await self.finishCapture(result: result, options: options)
                    await self.restoreFocus(windowInfo.focusRestorer, after: nil)
                } catch {
                    await self.handleCaptureError(error, context: "Window capture")
                    await self.restoreFocus(windowInfo.focusRestorer, after: error)
                }
            }
        }, failure: { [weak self] error in
            // Window list couldn't be loaded (e.g. no Screen Recording permission).
            self?.windowSelectorController = nil
            self?.handleCaptureError(error, context: "Window selection")
        })
        windowSelectorController?.show()
    }

    private func captureScroll(options: CaptureOptions) {
        scrollCaptureCoordinator.start(options: options)
    }

    @MainActor
    func finishCapture(result: CaptureResult, options: CaptureOptions) {
        appState.isCapturing = false

        // Copy to clipboard
        if options.copyToClipboard {
            PasteboardHelper.copyImage(result.image, scale: result.scale)
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
                // Saves run concurrently, and encoding a large capture takes
                // long enough for a second same-second capture to pick the
                // same name. Reserving the name atomically keeps them apart.
                if let url = FileManager.default.reserveUniqueURL(
                    for: options.saveDirectory
                        .appendingPathComponent(filename)
                        .appendingPathExtension(options.format.fileExtension)
                ) {
                    if ImageUtils.save(
                        result.image,
                        to: url,
                        format: options.format,
                        jpegQuality: options.jpegQuality,
                        scale: result.scale
                    ) {
                        savedURL = url
                        fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
                    } else {
                        try? FileManager.default.removeItem(at: url)
                    }
                }
            }
            let thumbnail = ImageUtils.generateThumbnail(result.image)
            let saveFailed = options.saveToFile && savedURL == nil

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
                // After the post: the alert is modal, and the capture should
                // already be in the Quick Access overlay while it is up.
                if saveFailed {
                    MainActor.assumeIsolated {
                        CaptureFailureAlert.presentSaveFailure(directory: options.saveDirectory)
                    }
                }
            }
        }
    }

    /// Hands focus back to the app the user was in after a selector-driven
    /// capture, except when the error path is sending them to System Settings.
    @MainActor
    private func restoreFocus(_ focusRestorer: FocusRestorer?, after error: Error?) {
        if let captureError = error as? CaptureError, captureError == .permissionDenied {
            return
        }
        focusRestorer?.restore()
    }

    @MainActor
    private func handleCaptureError(_ error: Error, context: String) {
        appState.isCapturing = false

        if let captureError = error as? CaptureError, captureError == .permissionDenied {
            PermissionChecker.promptForScreenRecordingInSettings()
            return
        }

        print("\(context) failed: \(error)")
        CaptureFailureAlert.presentCaptureFailure(error, context: context)
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
