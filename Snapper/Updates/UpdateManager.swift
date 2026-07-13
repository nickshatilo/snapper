import AppKit
import Foundation
import Observation
import Sparkle

@MainActor
@Observable
final class UpdateManager {
    @ObservationIgnored
    private let updaterController: SPUStandardUpdaterController

    @ObservationIgnored
    private var observerToken: NSObjectProtocol?

    @ObservationIgnored
    private var updaterObservations: [NSKeyValueObservation] = []

    private(set) var automaticallyChecksForUpdates: Bool
    private(set) var automaticallyDownloadsUpdates: Bool
    private(set) var allowsAutomaticUpdates: Bool
    private(set) var canCheckForUpdates: Bool

    init(startingUpdater: Bool = true) {
        let controller = SPUStandardUpdaterController(
            startingUpdater: startingUpdater,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        updaterController = controller
        automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
        automaticallyDownloadsUpdates = controller.updater.automaticallyDownloadsUpdates
        allowsAutomaticUpdates = controller.updater.allowsAutomaticUpdates
        canCheckForUpdates = controller.updater.canCheckForUpdates

        observerToken = NotificationCenter.default.addObserver(
            forName: .checkForUpdates,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.checkForUpdates()
            }
        }

        observeUpdaterState()
    }

    deinit {
        if let observerToken {
            NotificationCenter.default.removeObserver(observerToken)
        }
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        updaterController.updater.automaticallyChecksForUpdates = enabled
        refreshState()
    }

    func setAutomaticallyDownloadsUpdates(_ enabled: Bool) {
        updaterController.updater.automaticallyDownloadsUpdates = enabled
        refreshState()
    }

    private func observeUpdaterState() {
        let updater = updaterController.updater
        updaterObservations = [
            updater.observe(\.automaticallyChecksForUpdates, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async {
                    self?.refreshState()
                }
            },
            updater.observe(\.automaticallyDownloadsUpdates, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async {
                    self?.refreshState()
                }
            },
            updater.observe(\.allowsAutomaticUpdates, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async {
                    self?.refreshState()
                }
            },
            updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async {
                    self?.refreshState()
                }
            }
        ]
    }

    private func refreshState() {
        let updater = updaterController.updater
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
        allowsAutomaticUpdates = updater.allowsAutomaticUpdates
        canCheckForUpdates = updater.canCheckForUpdates
    }
}
