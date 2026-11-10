import Darwin
import Foundation

extension FileManager {
    /// Claims `url` if nothing exists there, otherwise the first "name 2.ext",
    /// "name 3.ext", … that doesn't collide, so same-second captures never
    /// overwrite each other. The name is claimed atomically by creating an
    /// empty placeholder file with `O_CREAT | O_EXCL`, so concurrent callers
    /// always get distinct URLs. The caller writes over the placeholder and
    /// must remove it if that write fails. Returns nil if no file can be
    /// created in the directory.
    func reserveUniqueURL(for url: URL) -> URL? {
        enum Claim { case claimed, taken, failed }
        func claim(_ candidate: URL) -> Claim {
            let fd = open(candidate.path, O_CREAT | O_EXCL | O_WRONLY, 0o644)
            if fd >= 0 {
                close(fd)
                return .claimed
            }
            return errno == EEXIST ? .taken : .failed
        }

        for candidate in Self.uniqueURLCandidates(for: url) {
            switch claim(candidate) {
            case .claimed: return candidate
            case .taken: continue
            case .failed: return nil
            }
        }
        let fallback = Self.uniqueURLCandidate(for: url, counter: nil)
        return claim(fallback) == .claimed ? fallback : nil
    }

    /// `url`, then "name 2.ext" … "name 10000.ext", generated lazily.
    private static func uniqueURLCandidates(for url: URL) -> LazyMapSequence<ClosedRange<Int>, URL> {
        (1...10_000).lazy.map { counter in
            counter == 1 ? url : uniqueURLCandidate(for: url, counter: counter)
        }
    }

    /// "name N.ext", or "name <UUID>.ext" when `counter` is nil.
    private static func uniqueURLCandidate(for url: URL, counter: Int?) -> URL {
        let directory = url.deletingLastPathComponent()
        let baseName = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let suffix = counter.map(String.init) ?? UUID().uuidString
        var candidate = directory.appendingPathComponent("\(baseName) \(suffix)")
        if !ext.isEmpty {
            candidate = candidate.appendingPathExtension(ext)
        }
        return candidate
    }
}
