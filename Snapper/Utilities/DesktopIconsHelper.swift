import Foundation

enum DesktopIconsHelper {
    private static let finderBundleID = "com.apple.finder"
    private static let plistPath = NSHomeDirectory() + "/Library/Preferences/com.apple.finder.plist"

    static var areIconsVisible: Bool {
        let defaults = UserDefaults(suiteName: finderBundleID)
        return defaults?.bool(forKey: "CreateDesktop") ?? true
    }

    static func toggle() {
        let current = areIconsVisible
        setDesktopIcons(visible: !current)
    }

    static func setDesktopIcons(visible: Bool) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        process.arguments = ["write", finderBundleID, "CreateDesktop", "-bool", visible ? "true" : "false"]

        try? process.run()
        process.waitUntilExit()

        restartFinder()
    }

    private static func restartFinder() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Finder"]
        try? process.run()
        process.waitUntilExit()
    }
}
