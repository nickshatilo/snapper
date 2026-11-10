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
    private let cancelRequested = LockedFlag()

    /// Backstops for endless content (infinite feeds): the session ends
    /// gracefully with whatever was captured.
    private let maxScrollSteps = 300
    /// Consecutive steps that produced no verified, stitchable motion before
    /// the session gives up.
    private let maxConsecutiveFailures = 5
    /// Wheel path: consecutive steps with no motion at all that count as
    /// having reached the end of the content.
    private let stationaryStepsForEnd = 2

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
        cancelRequested.reset()
        areaSelectorController?.close()
        areaSelectorController = AreaSelectorWindowController { [weak self] selection in
            guard let self else { return }
            self.areaSelectorController = nil

            guard let rect = selection?.rect else {
                Task { @MainActor in
                    self.onSessionEnd()
                }
                return
            }

            // Resolve the AppKit -> CG flip here, on the main thread, where
            // the screen geometry is read.
            let primaryScreenMaxY = CoordinateSpace.primaryScreenMaxY
            Task {
                await self.runCaptureSession(
                    appKitRect: rect,
                    primaryScreenMaxY: primaryScreenMaxY,
                    options: options
                )
            }
        }
        areaSelectorController?.show(freezeScreen: false, showMagnifier: options.showMagnifier)
    }

    private func runCaptureSession(
        appKitRect selectedAppKitRect: CGRect,
        primaryScreenMaxY: CGFloat,
        options: CaptureOptions
    ) async {
        // The selector hands back an AppKit bottom-left rect; everything
        // downstream (ScreenCaptureKit, AX, CGEvent) speaks CG top-left.
        let selectedRect = CoordinateSpace.appKitToCG(selectedAppKitRect, primaryScreenMaxY: primaryScreenMaxY)

        let stop = stopRequested
        let cancel = cancelRequested
        let controlPanel = await MainActor.run { () -> ScrollCaptureControlPanel in
            let panel = ScrollCaptureControlPanel(
                onStop: { stop.set() },
                onCancel: { cancel.set() }
            )
            panel.show(near: selectedAppKitRect)
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
                for: selectedRect,
                content: content,
                retinaScale: options.retina2x
            )

            // A stream covers one display. Keep the part of the selection on
            // the chosen display rather than streaming an out-of-bounds
            // source rect (black/garbage rows).
            let rect = selectedRect.intersection(context.displayFrame)
            guard !rect.isNull, rect.width >= 1, rect.height >= 1 else {
                throw ScrollCaptureError.selectionOffDisplay
            }

            let scrollPoint = CGPoint(x: rect.midX, y: rect.midY)
            let autoScroller = AutoScroller(
                target: AutoScroller.resolveTarget(
                    at: scrollPoint,
                    content: content
                ),
                region: rect
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
            var consecutiveFailures = 0
            var stationarySteps = 0
            var steps = 0
            var reachedEnd = false
            var isPaused = false

            await MainActor.run {
                controlPanel.state.statusText = "Auto-scrolling..."
            }

            scrollLoop: while !stop.isSet, !cancel.isSet, steps < maxScrollSteps, !stitcher.reachedMaxHeight {
                switch autoScroller.requestNextStep() {
                case .reachedEnd:
                    reachedEnd = true
                    break scrollLoop
                case .paused:
                    // Nothing was posted, so this tick counts toward no step,
                    // failure, or stationary limit; Stop/Esc are still checked
                    // by the loop condition.
                    if !isPaused {
                        isPaused = true
                        await MainActor.run {
                            controlPanel.state.statusText = "Paused: move the pointer over the region to continue"
                        }
                    }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    continue scrollLoop
                case .requested:
                    if isPaused {
                        isPaused = false
                        await MainActor.run {
                            controlPanel.state.statusText = "Auto-scrolling..."
                        }
                    }
                }
                steps += 1

                // Re-measure against the last accepted frame (without
                // scrolling again) until the step's motion is verified or
                // the frames stop changing.
                let measurement = await measureStep(
                    recorder: recorder,
                    estimator: estimator,
                    lastAcceptedFrame: lastAcceptedFrame,
                    isInterrupted: { stop.isSet || cancel.isSet }
                )

                switch measurement {
                case .interrupted:
                    break scrollLoop

                case let .moved(frame, estimate):
                    guard stitcher.append(frame: frame.image, verticalShift: estimate.verticalShift) else {
                        consecutiveFailures += 1
                        stationarySteps = 0
                        autoScroller.stepFailed()
                        break
                    }
                    consecutiveFailures = 0
                    stationarySteps = 0
                    autoScroller.adaptStep(
                        observedShift: estimate.verticalShift,
                        regionHeight: initialFrame.image.height
                    )
                    lastAcceptedFrame = frame
                    await MainActor.run {
                        controlPanel.state.statusText = "Captured \(stitcher.currentHeight) px..."
                    }

                case .stationary:
                    stationarySteps += 1
                    if autoScroller.usesWheelEvents {
                        // Wheel events give no end signal; content that stops
                        // moving means the bottom was reached (or it never
                        // scrolled: a single-frame capture, as on the AX path).
                        if stationarySteps >= stationaryStepsForEnd {
                            reachedEnd = true
                            break scrollLoop
                        }
                    } else {
                        consecutiveFailures += 1
                        autoScroller.stepProducedNoMotion()
                    }
                    await MainActor.run {
                        controlPanel.state.statusText = "Waiting for movement..."
                    }

                case .ambiguous:
                    stationarySteps = 0
                    consecutiveFailures += 1
                    autoScroller.stepFailed()
                    await MainActor.run {
                        controlPanel.state.statusText = "Retrying scroll step..."
                    }
                }

                if consecutiveFailures >= maxConsecutiveFailures {
                    break
                }
            }

            if cancel.isSet {
                return
            }

            // Content that fits without scrolling (immediate end) or a user
            // stop is a successful single-frame capture, not an error.
            guard stitcher.hasAppendedContent || reachedEnd || stop.isSet else {
                throw ScrollCaptureError.noConfirmedScrollMotion
            }

            let finalImage = stitcher.image
            let result = CaptureResult(
                image: finalImage,
                mode: .scroll,
                timestamp: Date(),
                sourceRect: rect,
                windowName: nil,
                applicationName: autoScroller.targetName,
                scale: rect.width > 0 ? CGFloat(finalImage.width) / rect.width : 1
            )

            await MainActor.run {
                self.finishCaptureHandler(result, options)
            }
        } catch {
            guard !cancel.isSet else { return }
            await MainActor.run {
                self.errorHandler(error, "Scroll capture")
            }
        }
    }

    private enum StepMeasurement {
        case moved(ScrollCapturedFrame, ScrollMotionEstimate)
        case stationary
        case ambiguous
        case interrupted
    }

    /// Waits for the step's motion to show up in the stream, comparing each
    /// new frame against the last accepted one. Frames caught before the
    /// scroll lands read as stationary, so a few attempts are made before
    /// concluding; no extra scroll input is issued in between.
    private func measureStep(
        recorder: ScrollCaptureRecorder,
        estimator: ScrollMotionEstimator,
        lastAcceptedFrame: ScrollCapturedFrame,
        isInterrupted: () -> Bool
    ) async -> StepMeasurement {
        var lastExaminedSequence = lastAcceptedFrame.sequence
        var verdict = StepMeasurement.stationary

        for attempt in 0..<3 {
            try? await Task.sleep(nanoseconds: attempt == 0 ? 160_000_000 : 120_000_000)
            if isInterrupted() {
                return .interrupted
            }

            // No new frame within the timeout: nothing on screen changed.
            guard let frame = await recorder.nextFrame(after: lastExaminedSequence, timeout: 1.0) else {
                break
            }
            lastExaminedSequence = frame.sequence

            switch estimator.analyze(previous: lastAcceptedFrame.image, current: frame.image) {
            case let .moved(estimate):
                if estimate.confidence < 0.48 {
                    verdict = .ambiguous
                } else if estimate.verticalShift < 6 {
                    // Real but too small to stitch: treat like no motion.
                    verdict = .stationary
                } else {
                    return .moved(frame, estimate)
                }
            case .stationary:
                verdict = .stationary
            case .ambiguous:
                verdict = .ambiguous
            }
        }

        return isInterrupted() ? .interrupted : verdict
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
    case selectionOffDisplay

    var errorDescription: String? {
        switch self {
        case .noInitialFrame:
            return "Scroll capture couldn't start the video stream."
        case .noConfirmedScrollMotion:
            return "Snapper couldn't detect reliable scrolling in the selected region."
        case .selectionOffDisplay:
            return "The selected region isn't on a display that can be captured."
        }
    }
}
