import AppKit
import UniformTypeIdentifiers

enum ImageUtils {
    static func save(_ image: CGImage, to url: URL, format: ImageFormat, jpegQuality: Double = 0.9) -> Bool {
        let utType: UTType
        switch format {
        case .png: utType = .png
        case .jpeg: utType = .jpeg
        case .tiff: utType = .tiff
        }

        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, utType.identifier as CFString, 1, nil) else {
            return false
        }

        var properties: [CFString: Any] = [:]
        if format == .jpeg {
            properties[kCGImageDestinationLossyCompressionQuality] = jpegQuality
        }

        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }

    static func imageData(_ image: CGImage, format: ImageFormat, jpegQuality: Double = 0.9) -> Data? {
        let bitmapRep = NSBitmapImageRep(cgImage: image)
        switch format {
        case .png:
            return bitmapRep.representation(using: .png, properties: [:])
        case .jpeg:
            return bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: jpegQuality])
        case .tiff:
            return bitmapRep.representation(using: .tiff, properties: [:])
        }
    }

    static func cgImage(from nsImage: NSImage) -> CGImage? {
        nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    static func resize(_ image: CGImage, to size: CGSize) -> CGImage? {
        let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: image.bitsPerComponent,
            bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: image.bitmapInfo.rawValue
        )
        context?.interpolationQuality = .high
        context?.draw(image, in: CGRect(origin: .zero, size: size))
        return context?.makeImage()
    }

    static func generateThumbnail(_ image: CGImage, maxWidth: CGFloat = Constants.Defaults.thumbnailWidth) -> CGImage? {
        let aspectRatio = CGFloat(image.height) / CGFloat(image.width)
        let targetWidth = min(maxWidth, CGFloat(image.width))
        let targetHeight = targetWidth * aspectRatio
        return resize(image, to: CGSize(width: targetWidth, height: targetHeight))
    }
}
