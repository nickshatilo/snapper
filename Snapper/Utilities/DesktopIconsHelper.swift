import Foundation

enum DesktopIconsHelper {
    private static let finderBundleID = "com.apple.finder"
    private static let workerQueue = DispatchQueue(label: "com.snapper.desktopicons", qos: .utility)

    static var areIconsVisible: Bool {
        guard let defaults = UserDefaults(suiteName: finderBundleID) else {
            return true
        }
        return defaults.object(forKey: "CreateDesktop") as? Bool ?? true
    }

    static func toggle() {
        let current = areIconsVisible
        setDesktopIcons(visible: !current)
    }

    static func setDesktopIcons(visible: Bool, completion: ((Bool) -> Void)? = nil) {
        workerQueue.async {
            if areIconsVisible == visible {
                DispatchQueue.main.async {
                    completion?(true)
                }
                return
            }

            let defaults = UserDefaults(suiteName: finderBundleID)
            defaults?.set(visible, forKey: "CreateDesktop")
            CFPreferencesAppSynchronize(finderBundleID as CFString)
            let didRestartFinder = restartFinder()

            DispatchQueue.main.async {
                completion?(didRestartFinder)
            }
        }
    }

    @discardableResult
    private static func restartFinder() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Finder"]
        do {
            try process.run()
        } catch {
            return false
        }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
