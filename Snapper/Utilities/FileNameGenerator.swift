import Foundation

enum FileNameGenerator {
    private static var counter: Int = {
        UserDefaults.standard.integer(forKey: "fileNameCounter")
    }()

    static func generate(pattern: String, mode: CaptureMode, appName: String? = nil) -> String {
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateStr = dateFormatter.string(from: now)

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH.mm.ss"
        let timeStr = timeFormatter.string(from: now)

        counter += 1
        UserDefaults.standard.set(counter, forKey: "fileNameCounter")

        var result = pattern
        result = result.replacingOccurrences(of: "{date}", with: dateStr)
        result = result.replacingOccurrences(of: "{time}", with: timeStr)
        result = result.replacingOccurrences(of: "{counter}", with: String(format: "%04d", counter))
        result = result.replacingOccurrences(of: "{app}", with: appName ?? "Unknown")
        result = result.replacingOccurrences(of: "{type}", with: mode.displayName)

        // Sanitize filename
        let invalidChars = CharacterSet(charactersIn: "/\\:*?\"<>|")
        result = result.components(separatedBy: invalidChars).joined(separator: "_")

        return result
    }
}
