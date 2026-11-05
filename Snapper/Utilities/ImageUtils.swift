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
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        guard width > 0, height > 0 else { return nil }

        // Use a standard pixel format rather than inheriting the source's;
        // CGContext rejects several source formats (e.g. float components),
        // which would silently drop the thumbnail.
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: outputColorSpace(for: [image]),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.interpolationQuality = .high
        context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context?.makeImage()
    }

    /// Colour space for an RGBA bitmap context that redraws `images`: the first
    /// image's own space (e.g. the display's P3 profile) when an 8-bit RGB
    /// context can render into it, else sRGB. Using DeviceRGB instead would drop
    /// the display profile and shift colours.
    static func outputColorSpace(for images: [CGImage]) -> CGColorSpace {
        if let space = images.first?.colorSpace, space.model == .rgb, space.supportsOutput {
            return space
        }
        return CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    }

    static func generateThumbnail(_ image: CGImage, maxWidth: CGFloat = Constants.Defaults.thumbnailWidth) -> CGImage? {
        guard image.width > 0, image.height > 0 else { return nil }
        let aspectRatio = CGFloat(image.height) / CGFloat(image.width)
        let targetWidth = min(maxWidth, CGFloat(image.width))
        let targetHeight = targetWidth * aspectRatio
        return resize(image, to: CGSize(width: targetWidth, height: targetHeight))
    }
}
