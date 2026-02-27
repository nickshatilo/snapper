import AppKit
import Foundation

final class UpdateManager {
    private let releasesURL = URL(string: "https://github.com/nickshatilo/snapper/releases")
    private var observerToken: NSObjectProtocol?

    init() {
        observerToken = NotificationCenter.default.addObserver(
            forName: .checkForUpdates,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.checkForUpdates()
        }
    }

    deinit {
        if let observerToken {
            NotificationCenter.default.removeObserver(observerToken)
        }
    }

    func checkForUpdates() {
        guard let releasesURL else { return }
        NSWorkspace.shared.open(releasesURL)
    }

    var automaticallyChecksForUpdates: Bool {
        get { UserDefaults.standard.object(forKey: Constants.Keys.autoCheckUpdates) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: Constants.Keys.autoCheckUpdates) }
    }
}
