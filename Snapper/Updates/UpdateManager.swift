import Foundation

final class UpdateManager {
    // Sparkle integration will be configured when the SPM package is added.
    // For now, this is a placeholder that will wrap SPUStandardUpdaterController.

    init() {
        NotificationCenter.default.addObserver(
            forName: .checkForUpdates,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.checkForUpdates()
        }
    }

    func checkForUpdates() {
        // TODO: Integrate Sparkle SPUStandardUpdaterController
        // let updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        // updaterController.checkForUpdates(nil)
        print("Check for updates triggered (Sparkle not yet configured)")
    }

    var automaticallyChecksForUpdates: Bool {
        get { UserDefaults.standard.object(forKey: Constants.Keys.autoCheckUpdates) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Constants.Keys.autoCheckUpdates) }
    }
}
