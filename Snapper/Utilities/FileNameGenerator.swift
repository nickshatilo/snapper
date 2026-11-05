import Foundation

enum FileNameGenerator {
    private static let lock = NSLock()
    private static var counter: Int = {
        UserDefaults.standard.integer(forKey: "fileNameCounter")
    }()
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH.mm.ss"
        return formatter
    }()

    static func generate(pattern: String, mode: CaptureMode, appName: String? = nil) -> String {
        let name = expand(pattern: pattern, mode: mode, appName: appName)
        // An empty name would make `saveDirectory/"" + ".png"` resolve to a
        // sibling "<directory>.png" outside the save folder.
        if name.isEmpty {
            return expand(pattern: Constants.Defaults.filenamePattern, mode: mode, appName: appName)
        }
        return name
    }

    private static func expand(pattern: String, mode: CaptureMode, appName: String?) -> String {
        let pattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Constants.Defaults.filenamePattern
            : pattern
        let now = Date()
        let dateStr: String
        let timeStr: String
        let currentCounter: Int

        lock.lock()
        defer { lock.unlock() }
        dateStr = dateFormatter.string(from: now)
        timeStr = timeFormatter.string(from: now)
        counter += 1
        currentCounter = counter
        UserDefaults.standard.set(currentCounter, forKey: "fileNameCounter")

        var result = pattern
        result = result.replacingOccurrences(of: "{date}", with: dateStr)
        result = result.replacingOccurrences(of: "{time}", with: timeStr)
        result = result.replacingOccurrences(of: "{counter}", with: String(format: "%04d", currentCounter))
        result = result.replacingOccurrences(of: "{app}", with: appName ?? "Unknown")
        result = result.replacingOccurrences(of: "{type}", with: mode.displayName)

        // Sanitize filename
        let invalidChars = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.newlines).union(.controlCharacters)
        result = result.components(separatedBy: invalidChars).joined(separator: "_")
        // Leading dots would hide the file; surrounding whitespace is invisible
        // in Finder and makes names that look identical differ.
        result = result.trimmingCharacters(in: .whitespaces)
        while result.hasPrefix(".") {
            result.removeFirst()
        }
        result = result.trimmingCharacters(in: .whitespaces)
        // Keep room for " 10000.jpeg" within the 255-byte file-name limit.
        while result.utf8.count > 240 {
            result.removeLast()
        }

        return result
    }
}
