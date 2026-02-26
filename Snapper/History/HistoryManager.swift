import AppKit
import SwiftData

final class HistoryManager {
    let modelContainer: ModelContainer

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

    @MainActor
    func saveCapture(result: CaptureResult, savedURL: URL?, thumbnailURL: URL?) {
        let record = CaptureRecord(
            captureType: result.mode.rawValue,
            width: result.width,
            height: result.height,
            filePath: savedURL?.path ?? "",
            thumbnailPath: thumbnailURL?.path,
            fileSize: savedURL.flatMap { url in
                (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
            } ?? 0,
            applicationName: result.applicationName
        )
        modelContainer.mainContext.insert(record)
        try? modelContainer.mainContext.save()
    }

    @MainActor
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

    @MainActor
    func delete(_ record: CaptureRecord) {
        // Delete associated files
        if !record.filePath.isEmpty {
            try? FileManager.default.removeItem(atPath: record.filePath)
        }
        if let thumbPath = record.thumbnailPath {
            try? FileManager.default.removeItem(atPath: thumbPath)
        }
        modelContainer.mainContext.delete(record)
        try? modelContainer.mainContext.save()
    }

    @MainActor
    func deleteOlderThan(days: Int) {
        guard days > 0 else { return }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let predicate = #Predicate<CaptureRecord> { $0.timestamp < cutoff }
        let descriptor = FetchDescriptor<CaptureRecord>(predicate: predicate)

        guard let records = try? modelContainer.mainContext.fetch(descriptor) else { return }
        for record in records {
            delete(record)
        }
    }

    @MainActor
    func totalStorageSize() -> Int {
        let records = fetchAll()
        return records.reduce(0) { $0 + $1.fileSize }
    }
}
