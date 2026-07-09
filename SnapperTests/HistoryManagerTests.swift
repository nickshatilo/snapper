import XCTest
@testable import Snapper

final class HistoryManagerTests: XCTestCase {
    func testRemovingManagedFilesPreservesExportAndDeletesThumbnail() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let exportedURL = directory.appendingPathComponent("exported.png")
        let thumbnailURL = directory.appendingPathComponent("thumbnail.png")
        try Data("export".utf8).write(to: exportedURL)
        try Data("thumbnail".utf8).write(to: thumbnailURL)

        let record = CaptureRecord(
            captureType: "area",
            width: 100,
            height: 100,
            filePath: exportedURL.path,
            thumbnailPath: thumbnailURL.path
        )

        HistoryManager.removeManagedFiles(for: record)

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: exportedURL.path),
            "Removing history must not delete the user's exported screenshot"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: thumbnailURL.path),
            "Removing history should delete the app-owned thumbnail"
        )
    }
}
