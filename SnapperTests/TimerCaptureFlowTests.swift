import XCTest
@testable import Snapper

final class TimerCaptureFlowTests: XCTestCase {
    private var defaults: UserDefaults!
    private var notificationCenter: NotificationCenter!
    private var appState: AppState!
    private var coordinator: CaptureCoordinator!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: #function)
        defaults.removePersistentDomain(forName: #function)
        notificationCenter = NotificationCenter()
        appState = AppState(defaults: defaults)
        coordinator = CaptureCoordinator(appState: appState, notificationCenter: notificationCenter)
    }

    override func tearDown() {
        coordinator = nil
        defaults.removePersistentDomain(forName: #function)
        appState = nil
        notificationCenter = nil
        defaults = nil
        super.tearDown()
    }

    func testTimerRequestReservesCaptureAndRejectsReentry() {
        var countdownRequests: [TimerCaptureRequest] = []
        let token = notificationCenter.addObserver(
            forName: .startTimerCapture,
            object: nil,
            queue: .main
        ) { notification in
            if let request = notification.object as? TimerCaptureRequest {
                countdownRequests.append(request)
            }
        }
        defer { notificationCenter.removeObserver(token) }

        notificationCenter.post(
            name: .startCapture,
            object: TimerCaptureRequest(seconds: 5, mode: .area)
        )
        notificationCenter.post(name: .startCapture, object: CaptureMode.fullscreen)

        XCTAssertTrue(appState.isCapturing)
        XCTAssertEqual(countdownRequests.count, 1)
        XCTAssertEqual(countdownRequests.first?.seconds, 5)
        XCTAssertEqual(countdownRequests.first?.mode, .area)
    }

    func testCountdownCompletionContinuesUsingExistingReservation() {
        var ocrStarts = 0
        let token = notificationCenter.addObserver(
            forName: .startOCRCapture,
            object: nil,
            queue: .main
        ) { _ in
            ocrStarts += 1
        }
        defer { notificationCenter.removeObserver(token) }

        notificationCenter.post(
            name: .startCapture,
            object: TimerCaptureRequest(seconds: 3, mode: .ocr)
        )
        notificationCenter.post(name: .timerCaptureDidFinish, object: CaptureMode.ocr)

        XCTAssertEqual(ocrStarts, 1)
        XCTAssertTrue(appState.isCapturing)

        notificationCenter.post(name: .ocrCaptureDidFinish, object: nil)
        XCTAssertFalse(appState.isCapturing)
    }

    func testCancelledCountdownReleasesCaptureReservation() {
        notificationCenter.post(
            name: .startCapture,
            object: TimerCaptureRequest(seconds: 3, mode: .fullscreen)
        )
        XCTAssertTrue(appState.isCapturing)

        notificationCenter.post(name: .timerCaptureDidFinish, object: nil)

        XCTAssertFalse(appState.isCapturing)
    }
}
