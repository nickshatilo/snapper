import Foundation

extension FileManager {
    /// Returns `url` unchanged if nothing exists there, otherwise the first
    /// "name 2.ext", "name 3.ext", … that doesn't collide, so same-second
    /// captures never overwrite each other.
    func uniqueURL(for url: URL) -> URL {
        guard fileExists(atPath: url.path) else { return url }

        let directory = url.deletingLastPathComponent()
        let baseName = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension

        for counter in 2...10_000 {
            var candidate = directory.appendingPathComponent("\(baseName) \(counter)")
            if !ext.isEmpty {
                candidate = candidate.appendingPathExtension(ext)
            }
            if !fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        var fallback = directory.appendingPathComponent("\(baseName) \(UUID().uuidString)")
        if !ext.isEmpty {
            fallback = fallback.appendingPathExtension(ext)
        }
        return fallback
    }
}
