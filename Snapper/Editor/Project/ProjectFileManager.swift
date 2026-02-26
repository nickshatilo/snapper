import AppKit

enum ProjectFileManager {
    static let fileExtension = "snapper"

    static func save(project: SnapperProject, image: CGImage, to url: URL) throws {
        // Create bundle directory
        let bundleURL = url.appendingPathExtension(fileExtension)
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)

        // Save original image
        let imageURL = bundleURL.appendingPathComponent(project.originalImageFilename)
        guard ImageUtils.save(image, to: imageURL, format: .png) else {
            throw ProjectError.saveFailed
        }

        // Save project metadata
        let projectURL = bundleURL.appendingPathComponent("project.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(project)
        try data.write(to: projectURL)

        // Create exports directory
        let exportsURL = bundleURL.appendingPathComponent("exports")
        try FileManager.default.createDirectory(at: exportsURL, withIntermediateDirectories: true)
    }

    static func load(from url: URL) throws -> (SnapperProject, CGImage) {
        let projectURL = url.appendingPathComponent("project.json")
        let data = try Data(contentsOf: projectURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let project = try decoder.decode(SnapperProject.self, from: data)

        let imageURL = url.appendingPathComponent(project.originalImageFilename)
        guard let nsImage = NSImage(contentsOf: imageURL),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ProjectError.imageNotFound
        }

        return (project, cgImage)
    }
}

enum ProjectError: Error, LocalizedError {
    case saveFailed
    case imageNotFound

    var errorDescription: String? {
        switch self {
        case .saveFailed: return "Failed to save project"
        case .imageNotFound: return "Original image not found in project bundle"
        }
    }
}
