import Foundation
import SwiftData

@Model
final class CaptureRecord {
    var id: UUID
    var timestamp: Date
    var captureType: String
    var width: Int
    var height: Int
    var filePath: String
    var thumbnailPath: String?
    var fileSize: Int
    var tags: [String]
    var ocrText: String?
    var applicationName: String?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        captureType: String,
        width: Int,
        height: Int,
        filePath: String,
        thumbnailPath: String? = nil,
        fileSize: Int = 0,
        tags: [String] = [],
        ocrText: String? = nil,
        applicationName: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.captureType = captureType
        self.width = width
        self.height = height
        self.filePath = filePath
        self.thumbnailPath = thumbnailPath
        self.fileSize = fileSize
        self.tags = tags
        self.ocrText = ocrText
        self.applicationName = applicationName
    }
}
