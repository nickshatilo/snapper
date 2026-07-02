import AppKit
import ScreenCaptureKit

final class ScrollCaptureCoordinator {
    private let appState: AppState
    private let captureService = ScreenCaptureService()
    private let finishCaptureHandler: @MainActor (CaptureResult, CaptureOptions) -> Void
    private let errorHandler: @MainActor (Error, String) -> Void
    private let onSessionEnd: @MainActor () -> Void

    private var areaSelectorController: AreaSelectorWindowController?
    private let stopRequested = LockedFlag()

    /// Backstops for endless content (infinite feeds): the session ends
    /// gracefully with whatever was captured.
    private let maxScrollSteps = 300

    init(
        appState: AppState,
        finishCapture: @escaping @MainActor (CaptureResult, CaptureOptions) -> Void,
        handleError: @escaping @MainActor (Error, String) -> Void,
        onSessionEnd: @escaping @MainActor () -> Void
    ) {
        self.appState = appState
        self.finishCaptureHandler = finishCapture
        self.errorHandler = handleError
        self.onSessionEnd = onSessionEnd
    }

    func start(options: CaptureOptions) {
        stopRequested.reset()
        areaSelectorController?.close()
        areaSelectorController = AreaSelectorWindowController { [weak self] rect in
            guard let self else { return }
            self.areaSelectorController = nil

            guard let rect else {
                Task { @MainActor in
                    self.onSessionEnd()
                }
                return
            }

            Task {
                await self.runCaptureSession(appKitRect: rect, options: options)
            }
        }
        areaSelectorController?.show(freezeScreen: false, showMagnifier: options.showMagnifier)
    }

    private func runCaptureSession(appKitRect: CGRect, options: CaptureOptions) async {
        // The selector hands back an AppKit bottom-left rect; everything
        // downstream (ScreenCaptureKit, AX, CGEvent) speaks CG top-left.
        let rect = CoordinateSpace.appKitToCG(appKitRect)

        let stop = stopRequested
        let controlPanel = await MainActor.run { () -> ScrollCaptureControlPanel in
            let panel = ScrollCaptureControlPanel {
                stop.set()
            }
            panel.show(near: appKitRect)
            panel.state.statusText = "Preparing scroll capture..."
            return panel
        }

        defer {
            Task { @MainActor in
                controlPanel.close()
                self.onSessionEnd()
            }
        }

        do {
            let content = try await captureService.getShareableContent()
            let context = try await captureService.prepareRectCapture(
                for: rect,
                content: content,
                retinaScale: options.retina2x
            )

            let scrollPoint = CGPoint(x: rect.midX, y: rect.midY)
            let autoScroller = AutoScroller(
                target: AutoScroller.resolveTarget(
                    at: scrollPoint,
                    content: content
                ),
                regionHeightPoints: rect.height
            )
            autoScroller.prepareForScrolling()

            await MainActor.run {
                controlPanel.state.statusText = "Starting capture stream..."
            }

            let recorder = ScrollCaptureRecorder()
            try await recorder.startCapturing(rect: rect, context: context)
            defer {
                Task {
                    await recorder.stopCapturing()
                }
            }

            guard let initialFrame = await recorder.nextFrame(after: 0, timeout: 2.0) else {
                throw ScrollCaptureError.noInitialFrame
            }

            let stitcher = ScrollStitcher(initialImage: initialFrame.image)
            let estimator = ScrollMotionEstimator()
            var lastAcceptedFrame = initialFrame
            var noFrameFailures = 0
            var motionFailures = 0
            var steps = 0
            var reachedEnd = false

            await MainActor.run {
                controlPanel.state.statusText = "Auto-scrolling..."
            }

            while !stop.isSet, steps < maxScrollSteps, !stitcher.reachedMaxHeight {
                if case .reachedEnd = autoScroller.requestNextStep() {
                    reachedEnd = true
                    break
                }
                steps += 1

                try? await Task.sleep(nanoseconds: 160_000_000)

                guard let nextFrame = await recorder.nextFrame(after: lastAcceptedFrame.sequence, timeout: 1.25) else {
                    noFrameFailures += 1
                    if noFrameFailures >= 3 {
                        break
                    }
                    await MainActor.run {
                        controlPanel.state.statusText = "Waiting for movement..."
                    }
                    continue
                }
                noFrameFailures = 0

                guard let estimate = estimator.estimate(previous: lastAcceptedFrame.image, current: nextFrame.image),
                      estimate.verticalShift >= 6,
                      estimate.confidence >= 0.48 else {
                    motionFailures += 1
                    if motionFailures >= 4 {
                        break
                    }
                    await MainActor.run {
                        controlPanel.state.statusText = "Retrying scroll step..."
                    }
                    continue
                }

                guard stitcher.append(frame: nextFrame.image, verticalShift: estimate.verticalShift) else {
                    motionFailures += 1
                    if motionFailures >= 4 {
                        break
                    }
                    continue
                }

                motionFailures = 0
                autoScroller.adaptStep(
                    observedShift: estimate.verticalShift,
                    regionHeight: initialFrame.image.height
                )
                lastAcceptedFrame = nextFrame
                await MainActor.run {
                    controlPanel.state.statusText = "Captured \(stitcher.currentHeight) px..."
                }
            }

            // Content that fits without scrolling (immediate reachedEnd) or a
            // user stop is a successful single-frame capture, not an error.
            guard stitcher.hasAppendedContent || reachedEnd || stop.isSet else {
                throw ScrollCaptureError.noConfirmedScrollMotion
            }

            let finalImage = stitcher.image
            let result = CaptureResult(
                image: finalImage,
                mode: .scroll,
                timestamp: Date(),
                sourceRect: appKitRect,
                windowName: nil,
                applicationName: autoScroller.targetName,
                scale: rect.width > 0 ? CGFloat(finalImage.width) / rect.width : 1
            )

            await MainActor.run {
                self.finishCaptureHandler(result, options)
            }
        } catch {
            await MainActor.run {
                self.errorHandler(error, "Scroll capture")
            }
        }
    }
}

/// Set from the main thread (Stop button), read from the capture loop.
private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.withLock { value }
    }

    func set() {
        lock.withLock { value = true }
    }

    func reset() {
        lock.withLock { value = false }
    }
}

private enum ScrollCaptureError: LocalizedError {
    case noInitialFrame
    case noConfirmedScrollMotion

    var errorDescription: String? {
        switch self {
        case .noInitialFrame:
            return "Scroll capture couldn't start the video stream."
        case .noConfirmedScrollMotion:
            return "Snapper couldn't detect reliable scrolling in the selected region."
        }
    }
}
