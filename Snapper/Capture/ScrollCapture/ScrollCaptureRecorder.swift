import CoreImage
import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit

struct ScrollCapturedFrame {
    let sequence: Int
    let image: CGImage
}

final class ScrollCaptureRecorder: NSObject, SCStreamOutput, SCStreamDelegate {
    private let ciContext = CIContext(options: nil)
    private let frameStore = ScrollFrameStore()
    private let outputQueue = DispatchQueue(label: "com.snapper.scrollcapture.output")
    private var stream: SCStream?
    private var nextSequence = 0

    func startCapturing(
        rect: CGRect,
        context: ScreenCaptureService.RectCaptureContext,
        framesPerSecond: Int = 15
    ) async throws {
        let configuration = SCStreamConfiguration()
        configuration.showsCursor = false
        configuration.captureResolution = .best
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.queueDepth = 3
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(1, framesPerSecond)))
        // rect and displayFrame are CG top-left global; sourceRect wants
        // top-left display-relative points.
        configuration.sourceRect = CGRect(
            x: rect.minX - context.displayFrame.minX,
            y: rect.minY - context.displayFrame.minY,
            width: rect.width,
            height: rect.height
        )
        configuration.width = max(1, Int((rect.width * context.displayScale).rounded()))
        configuration.height = max(1, Int((rect.height * context.displayScale).rounded()))

        let stream = SCStream(
            filter: context.filter,
            configuration: configuration,
            delegate: self
        )
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: outputQueue)
        try await stream.startCapture()
        self.stream = stream
    }

    func stopCapturing() async {
        guard let stream else { return }
        try? stream.removeStreamOutput(self, type: .screen)
        try? await stream.stopCapture()
        self.stream = nil
        await frameStore.finish()
    }

    func nextFrame(after sequence: Int, timeout: TimeInterval) async -> ScrollCapturedFrame? {
        await frameStore.waitForNextFrame(after: sequence, timeout: timeout)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("Scroll capture stream stopped: \(error)")
        Task {
            await frameStore.finish()
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              sampleBuffer.isValid,
              let pixelBuffer = sampleBuffer.imageBuffer else {
            return
        }

        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(image, from: image.extent) else {
            return
        }

        // outputQueue is serial, so sequence assignment is ordered here; the
        // store's monotonic guard handles any reordering of the async hops.
        // Snapshot the frame (sequence + image) before the async hop — reading
        // self.nextSequence inside the Task would capture whatever value it holds
        // when the task later runs, letting two frames collide on one sequence.
        nextSequence += 1
        let frame = ScrollCapturedFrame(sequence: nextSequence, image: cgImage)
        Task {
            await frameStore.store(frame)
        }
    }
}

actor ScrollFrameStore {
    private var latestFrame: ScrollCapturedFrame?
    private var isFinished = false
    private var waiters: [Int: (afterSequence: Int, continuation: CheckedContinuation<ScrollCapturedFrame?, Never>)] = [:]
    private var nextWaiterID = 0

    func store(_ frame: ScrollCapturedFrame) {
        // Unstructured tasks can land out of order; never regress to an older frame.
        guard frame.sequence > (latestFrame?.sequence ?? 0) else { return }
        latestFrame = frame

        for (id, waiter) in waiters where frame.sequence > waiter.afterSequence {
            waiters.removeValue(forKey: id)
            waiter.continuation.resume(returning: frame)
        }
    }

    func finish() {
        isFinished = true
        for (_, waiter) in waiters {
            waiter.continuation.resume(returning: nil)
        }
        waiters.removeAll()
    }

    func waitForNextFrame(after sequence: Int, timeout: TimeInterval) async -> ScrollCapturedFrame? {
        if let latestFrame, latestFrame.sequence > sequence {
            return latestFrame
        }
        guard !isFinished else { return nil }

        let waiterID = nextWaiterID
        nextWaiterID += 1

        return await withCheckedContinuation { continuation in
            waiters[waiterID] = (sequence, continuation)
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self.expireWaiter(id: waiterID)
            }
        }
    }

    private func expireWaiter(id: Int) {
        guard let waiter = waiters.removeValue(forKey: id) else { return }
        waiter.continuation.resume(returning: nil)
    }
}
