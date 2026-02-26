import AppKit

final class ScrollingCaptureController {
    private var areaSelectorController: AreaSelectorWindowController?
    private let captureService = ScreenCaptureService()
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState

        NotificationCenter.default.addObserver(
            forName: .startScrollingCapture,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.start(options: notification.object as? CaptureOptions ?? CaptureOptions())
        }
    }

    func start(options: CaptureOptions) {
        areaSelectorController = AreaSelectorWindowController { [weak self] rect in
            guard let self else { return }
            self.areaSelectorController?.close()
            self.areaSelectorController = nil

            guard let rect else { return }

            Task {
                await self.performScrollingCapture(rect: rect, options: options)
            }
        }
        areaSelectorController?.show(freezeScreen: false)
    }

    @MainActor
    private func performScrollingCapture(rect: CGRect, options: CaptureOptions) async {
        if !PermissionChecker.isAccessibilityGranted() {
            let granted = PermissionChecker.requestAccessibility()
            if !granted {
                PermissionChecker.openAccessibilitySettings()
                return
            }
        }

        var capturedImages: [CGImage] = []
        let maxScrolls = 20
        let scrollDelay: UInt64 = 500_000_000 // 0.5 seconds
        let scrollPoint = CGPoint(x: rect.midX, y: rect.midY)
        var unchangedFrameCount = 0

        // Bring the target content under the selected area into focus once.
        let targetPID = ScrollSimulator.focus(at: scrollPoint)
        try? await Task.sleep(nanoseconds: 250_000_000)

        for _ in 0..<maxScrolls {
            do {
                let image = try await captureService.captureRect(rect)
                capturedImages.append(image)

                // Check if we've reached the end (image hasn't changed)
                if capturedImages.count >= 2 {
                    let prev = capturedImages[capturedImages.count - 2]
                    let curr = capturedImages[capturedImages.count - 1]
                    if imagesAreSimilar(prev, curr) {
                        capturedImages.removeLast()
                        unchangedFrameCount += 1

                        // Retry with a stronger fallback before deciding we reached the end.
                        if unchangedFrameCount >= 3 {
                            break
                        }

                        _ = ScrollSimulator.pageDown(targetPID: targetPID)
                        try await Task.sleep(nanoseconds: scrollDelay)
                        continue
                    }
                    unchangedFrameCount = 0
                }

                // Scroll down
                _ = ScrollSimulator.scrollDown(amount: 12, at: scrollPoint, targetPID: targetPID)
                try await Task.sleep(nanoseconds: scrollDelay)
            } catch {
                if let captureError = error as? CaptureError, captureError == .permissionDenied {
                    PermissionChecker.promptForScreenRecordingInSettings()
                    return
                }
                print("Scrolling capture frame failed: \(error)")
                break
            }
        }

        guard let firstImage = capturedImages.first else {
            print("Scrolling capture produced no frames")
            return
        }

        let finalImage: CGImage
        if capturedImages.count >= 2 {
            finalImage = ImageStitcher.stitch(capturedImages) ?? firstImage
        } else {
            finalImage = firstImage
        }

        let result = CaptureResult(
            image: finalImage,
            mode: .scrolling,
            timestamp: Date(),
            sourceRect: rect,
            windowName: nil,
            applicationName: nil
        )

        var savedURL: URL?
        if options.saveToFile {
            let filename = FileNameGenerator.generate(pattern: options.filenamePattern, mode: .scrolling)
            let url = options.saveDirectory
                .appendingPathComponent(filename)
                .appendingPathExtension(options.format.fileExtension)
            if ImageUtils.save(finalImage, to: url, format: options.format, jpegQuality: options.jpegQuality) {
                savedURL = url
            }
        }
        if options.copyToClipboard {
            PasteboardHelper.copyImage(finalImage)
        }
        if options.playSound {
            SoundPlayer.playCapture(options.captureSound)
        }

        NotificationCenter.default.post(
            name: .captureCompleted,
            object: CaptureCompletedInfo(result: result, savedURL: savedURL)
        )
    }

    private func imagesAreSimilar(_ a: CGImage, _ b: CGImage) -> Bool {
        guard a.width == b.width, a.height == b.height else { return false }
        // Simple comparison: check a horizontal strip in the middle
        let stripHeight = 10
        let y = a.height / 2
        guard let stripA = a.cropping(to: CGRect(x: 0, y: y, width: a.width, height: stripHeight)),
              let stripB = b.cropping(to: CGRect(x: 0, y: y, width: b.width, height: stripHeight)) else { return false }

        let dataA = NSBitmapImageRep(cgImage: stripA).representation(using: .png, properties: [:])
        let dataB = NSBitmapImageRep(cgImage: stripB).representation(using: .png, properties: [:])
        return dataA == dataB
    }
}
