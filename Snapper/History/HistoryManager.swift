import AppKit
import SwiftData

final class HistoryManager {
    let modelContainer: ModelContainer
    private let writeQueue = DispatchQueue(label: "com.snapper.history.write", qos: .utility)

    init() {
        let schema = Schema([CaptureRecord.self])
        let storeURL = Constants.App.historyDirectory.appendingPathComponent("History.store")
        let config = ModelConfiguration(url: storeURL)
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
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

        writeQueue.async { [modelContainer] in
            let context = ModelContext(modelContainer)
            let record = CaptureRecord(
                id: recordID,
                captureType: result.mode.rawValue,
                width: result.width,
                height: result.height,
                filePath: savedURL?.path ?? "",
                thumbnailPath: thumbnailURL?.path,
                fileSize: resolvedFileSize,
                applicationName: result.applicationName
            )
            context.insert(record)
            do {
                try context.save()
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .historyDidChange, object: nil)
                }
            } catch {
                print("History save failed: \(error)")
            }
        }
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

    @MainActor
    func search(query: String) -> [CaptureRecord] {
        let predicate = #Predicate<CaptureRecord> {
            $0.ocrText?.localizedStandardContains(query) == true ||
            $0.applicationName?.localizedStandardContains(query) == true ||
            $0.captureType.localizedStandardContains(query)
        }
        let descriptor = FetchDescriptor<CaptureRecord>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        return (try? modelContainer.mainContext.fetch(descriptor)) ?? []
    }

    func delete(_ record: CaptureRecord) {
        delete(recordID: record.id)
    }

    func delete(recordID: UUID) {
        writeQueue.async { [modelContainer] in
            let context = ModelContext(modelContainer)
            let predicate = #Predicate<CaptureRecord> { $0.id == recordID }
            let descriptor = FetchDescriptor<CaptureRecord>(predicate: predicate)
            guard let record = try? context.fetch(descriptor).first else { return }

            Self.removeFiles(for: record)
            context.delete(record)
            try? context.save()

            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .historyDidChange, object: nil)
            }
        }
    }

    func deleteOlderThan(days: Int) {
        guard days > 0 else { return }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        writeQueue.async { [modelContainer] in
            let context = ModelContext(modelContainer)
            let predicate = #Predicate<CaptureRecord> { $0.timestamp < cutoff }
            let descriptor = FetchDescriptor<CaptureRecord>(predicate: predicate)
            guard let records = try? context.fetch(descriptor), !records.isEmpty else { return }

            for record in records {
                Self.removeFiles(for: record)
                context.delete(record)
            }
            try? context.save()

            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .historyDidChange, object: nil)
            }
        }
    }

    @MainActor
    func totalStorageSize() -> Int {
        let records = fetchAll()
        return records.reduce(0) { $0 + $1.fileSize }
    }

    func clearAll() {
        writeQueue.async { [modelContainer] in
            let context = ModelContext(modelContainer)
            let descriptor = FetchDescriptor<CaptureRecord>()
            guard let records = try? context.fetch(descriptor), !records.isEmpty else { return }

            for record in records {
                Self.removeFiles(for: record)
                context.delete(record)
            }
            try? context.save()

            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .historyDidChange, object: nil)
            }
        }
    }

    private static func removeFiles(for record: CaptureRecord) {
        if !record.filePath.isEmpty {
            try? FileManager.default.removeItem(atPath: record.filePath)
        }
        if let thumbPath = record.thumbnailPath {
            try? FileManager.default.removeItem(atPath: thumbPath)
        }
    }
}

extension Notification.Name {
    static let historyDidChange = Notification.Name("historyDidChange")
}
