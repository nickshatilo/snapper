import AppKit
import SQLite3
import SwiftData

final class HistoryManager {
    let modelContainer: ModelContainer

    init(storeURL: URL = Constants.App.historyDirectory.appendingPathComponent("History.store")) {
        let schema = Schema([CaptureRecord.self])
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [ModelConfiguration(url: storeURL)])
            return
        } catch {
            print("History store failed to load: \(error)")
        }

        // A bad store must not crash every launch, but a transient failure
        // (lock, permissions, full disk) must not cost the user their history
        // either. Only a file that is itself damaged or unreadable by this
        // schema is moved aside (never deleted) and replaced; otherwise the
        // file is left untouched and this session's history lives in memory.
        if Self.diagnoseStore(at: storeURL) == .unusable, Self.moveStoreAside(at: storeURL) {
            print("Moved the unusable history store aside; starting a new one.")
            if let fresh = try? ModelContainer(for: schema, configurations: [ModelConfiguration(url: storeURL)]) {
                modelContainer = fresh
                return
            }
        }

        print("Using in-memory history for this session.")
        do {
            modelContainer = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
            )
        } catch {
            fatalError("Failed to create in-memory ModelContainer: \(error)")
        }
    }

    enum StoreDiagnosis: Equatable {
        /// The file is corrupt, not a database, or a healthy database that
        /// still failed to load (incompatible schema / failed migration).
        case unusable
        /// The failure isn't attributable to the file's contents.
        case transient
    }

    /// SwiftData's load error is opaque, so inspect the file directly.
    static func diagnoseStore(at storeURL: URL) -> StoreDiagnosis {
        let fileManager = FileManager.default
        let path = storeURL.path
        let directory = storeURL.deletingLastPathComponent().path
        guard fileManager.fileExists(atPath: path),
              fileManager.isReadableFile(atPath: path),
              fileManager.isWritableFile(atPath: path),
              fileManager.isWritableFile(atPath: directory) else {
            return .transient
        }

        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        let openStatus = sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE, nil)
        if openStatus != SQLITE_OK {
            return isCorruption(openStatus) ? .unusable : .transient
        }

        // quick_check reads every page; garbage files fail here with NOTADB.
        var statement: OpaquePointer?
        let prepareStatus = sqlite3_prepare_v2(db, "PRAGMA quick_check", -1, &statement, nil)
        guard prepareStatus == SQLITE_OK else {
            sqlite3_finalize(statement)
            return isCorruption(prepareStatus) ? .unusable : .transient
        }
        let stepStatus = sqlite3_step(statement)
        let firstRow = stepStatus == SQLITE_ROW ? sqlite3_column_text(statement, 0).map { String(cString: $0) } : nil
        sqlite3_finalize(statement)
        if stepStatus != SQLITE_ROW {
            return isCorruption(stepStatus) ? .unusable : .transient
        }
        if firstRow != "ok" {
            return .unusable
        }

        // A lock held by another process is transient.
        let lockStatus = sqlite3_exec(db, "BEGIN IMMEDIATE; ROLLBACK;", nil, nil, nil)
        if lockStatus != SQLITE_OK {
            return isCorruption(lockStatus) ? .unusable : .transient
        }

        // A healthy, unlocked, writable database that SwiftData still
        // refused: an incompatible or failed-migration schema.
        return .unusable
    }

    private static func isCorruption(_ status: Int32) -> Bool {
        let primary = status & 0xFF
        return primary == SQLITE_CORRUPT || primary == SQLITE_NOTADB
    }

    /// Renames the store and its SQLite sidecar files to
    /// "History.store.broken-<timestamp>[-wal|-shm]". Never deletes anything:
    /// if any rename fails, the ones already done are undone and it returns
    /// false, leaving the store exactly where it was.
    @discardableResult
    static func moveStoreAside(at storeURL: URL) -> Bool {
        let fileManager = FileManager.default
        let suffix = ".broken-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(8))"
        var moved: [(source: URL, destination: URL)] = []
        for sidecar in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: storeURL.path + sidecar)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            let destination = URL(fileURLWithPath: storeURL.path + suffix + sidecar)
            do {
                try fileManager.moveItem(at: source, to: destination)
                moved.append((source, destination))
            } catch {
                for item in moved.reversed() {
                    try? fileManager.moveItem(at: item.destination, to: item.source)
                }
                return false
            }
        }
        return true
    }

    func saveCapture(
        result: CaptureResult,
        savedURL: URL?,
        thumbnailURL: URL?,
        recordID: UUID = UUID(),
        fileSize: Int? = nil
    ) {
        let resolvedFileSize: Int
        if let fileSize {
            resolvedFileSize = max(0, fileSize)
        } else {
            resolvedFileSize = savedURL.flatMap { url in
                (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            } ?? 0
        }

        let captureType = result.mode.rawValue
        let width = result.width
        let height = result.height
        let filePath = savedURL?.path ?? ""
        let thumbPath = thumbnailURL?.path
        let appName = result.applicationName

        DispatchQueue.main.async { [modelContainer] in
            let record = CaptureRecord(
                id: recordID,
                captureType: captureType,
                width: width,
                height: height,
                filePath: filePath,
                thumbnailPath: thumbPath,
                fileSize: resolvedFileSize,
                applicationName: appName
            )
            modelContainer.mainContext.insert(record)
            try? modelContainer.mainContext.save()
            NotificationCenter.default.post(name: .historyDidChange, object: nil)
        }
    }

    /// One OCR at a time, at background priority, so a burst of captures
    /// doesn't run several Vision requests in parallel.
    private let ocrQueue = DispatchQueue(label: "com.snapper.history.ocr", qos: .background)
    /// Longest side of the copy kept for indexing. Below
    /// TextRecognitionService's own 4800px cap, so it isn't downscaled twice.
    static let ocrMaxDimension: CGFloat = 2400

    /// Recognizes text in a saved capture and stores it on the record so
    /// history search can match on screenshot text. Call off the main thread,
    /// after `saveCapture` (whose main-queue insert then precedes the lookup).
    /// Only a downscaled copy is retained while the job waits in the queue.
    func indexText(in image: CGImage, for recordID: UUID) {
        let ocrImage = Self.downscaledForOCR(image)
        ocrQueue.async { [modelContainer] in
            // Skip records deleted while this job was queued.
            guard Self.recordExists(recordID, in: modelContainer) else { return }

            let recognized = OCRResultBox()
            let done = DispatchSemaphore(value: 0)
            Task.detached(priority: .background) {
                recognized.text = try? await TextRecognitionService.recognizeText(in: ocrImage)
                done.signal()
            }
            done.wait()

            let text = recognized.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else { return }

            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    // The record may also have been deleted while OCR ran.
                    guard let record = Self.fetchRecord(recordID, in: modelContainer) else { return }
                    record.ocrText = text
                    try? modelContainer.mainContext.save()
                    NotificationCenter.default.post(name: .historyDidChange, object: nil)
                }
            }
        }
    }

    static func downscaledForOCR(_ image: CGImage) -> CGImage {
        let longest = CGFloat(max(image.width, image.height))
        guard longest > ocrMaxDimension else { return image }
        let scale = ocrMaxDimension / longest
        let size = CGSize(
            width: max(1, (CGFloat(image.width) * scale).rounded()),
            height: max(1, (CGFloat(image.height) * scale).rounded())
        )
        return ImageUtils.resize(image, to: size) ?? image
    }

    private static func recordExists(_ recordID: UUID, in modelContainer: ModelContainer) -> Bool {
        DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                fetchRecord(recordID, in: modelContainer) != nil
            }
        }
    }

    /// Written by the OCR task before it signals, read after the wait.
    private final class OCRResultBox: @unchecked Sendable {
        var text: String?
    }

    @MainActor
    private static func fetchRecord(_ recordID: UUID, in modelContainer: ModelContainer) -> CaptureRecord? {
        let predicate = #Predicate<CaptureRecord> { $0.id == recordID }
        let descriptor = FetchDescriptor<CaptureRecord>(predicate: predicate)
        return try? modelContainer.mainContext.fetch(descriptor).first
    }

    func saveThumbnail(_ image: CGImage, for recordID: UUID) -> URL? {
        let url = Constants.App.historyDirectory
            .appendingPathComponent("thumbnails")
            .appendingPathComponent("\(recordID.uuidString).png")

        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if ImageUtils.save(image, to: url, format: .png) {
            return url
        }
        return nil
    }

    @MainActor
    func fetchAll(sortedBy sortOrder: SortOrder = .reverse) -> [CaptureRecord] {
        let descriptor = FetchDescriptor<CaptureRecord>(
            sortBy: [SortDescriptor(\.timestamp, order: sortOrder)]
        )
        return (try? modelContainer.mainContext.fetch(descriptor)) ?? []
    }

    /// Points a record at the file its capture was saved to after the fact
    /// (captures taken with "Save to File" off start out with no file).
    func updateFile(recordID: UUID, url: URL, fileSize: Int) {
        let filePath = url.path
        let resolvedFileSize = max(0, fileSize)
        DispatchQueue.main.async { [modelContainer] in
            let predicate = #Predicate<CaptureRecord> { $0.id == recordID }
            let descriptor = FetchDescriptor<CaptureRecord>(predicate: predicate)
            guard let record = try? modelContainer.mainContext.fetch(descriptor).first else { return }

            record.filePath = filePath
            record.fileSize = resolvedFileSize
            try? modelContainer.mainContext.save()
            NotificationCenter.default.post(name: .historyDidChange, object: nil)
        }
    }

    func delete(_ record: CaptureRecord) {
        delete(recordID: record.id)
    }

    func delete(recordID: UUID) {
        DispatchQueue.main.async { [modelContainer] in
            let predicate = #Predicate<CaptureRecord> { $0.id == recordID }
            let descriptor = FetchDescriptor<CaptureRecord>(predicate: predicate)
            guard let record = try? modelContainer.mainContext.fetch(descriptor).first else { return }

            Self.removeManagedFiles(for: record)
            modelContainer.mainContext.delete(record)
            try? modelContainer.mainContext.save()
            NotificationCenter.default.post(name: .historyDidChange, object: nil)
        }
    }

    func deleteOlderThan(days: Int) {
        guard days > 0 else { return }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        DispatchQueue.main.async { [modelContainer] in
            let predicate = #Predicate<CaptureRecord> { $0.timestamp < cutoff }
            let descriptor = FetchDescriptor<CaptureRecord>(predicate: predicate)
            guard let records = try? modelContainer.mainContext.fetch(descriptor), !records.isEmpty else { return }

            for record in records {
                Self.removeManagedFiles(for: record)
                modelContainer.mainContext.delete(record)
            }
            try? modelContainer.mainContext.save()
            NotificationCenter.default.post(name: .historyDidChange, object: nil)
        }
    }

    func clearAll() {
        DispatchQueue.main.async { [modelContainer] in
            let descriptor = FetchDescriptor<CaptureRecord>()
            guard let records = try? modelContainer.mainContext.fetch(descriptor), !records.isEmpty else { return }

            for record in records {
                Self.removeManagedFiles(for: record)
                modelContainer.mainContext.delete(record)
            }
            try? modelContainer.mainContext.save()
            NotificationCenter.default.post(name: .historyDidChange, object: nil)
        }
    }

    static func removeManagedFiles(for record: CaptureRecord) {
        if let thumbPath = record.thumbnailPath {
            try? FileManager.default.removeItem(atPath: thumbPath)
        }
    }
}

/// Posted as the object of `.historyRecordFileSaved` when a capture that had
/// no file on disk is saved.
struct HistoryFileUpdate {
    let recordID: UUID
    let url: URL
    let fileSize: Int
}

extension Notification.Name {
    static let historyDidChange = Notification.Name("historyDidChange")
    static let historyRecordFileSaved = Notification.Name("historyRecordFileSaved")
}
