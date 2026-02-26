import AppKit

enum BackgroundRenderer {
    static func render(image: CGImage, template: BackgroundTemplate) -> CGImage? {
        let imgWidth = CGFloat(image.width)
        let imgHeight = CGFloat(image.height)
        let padding = template.padding * 2

        var canvasWidth = imgWidth + padding * 2
        var canvasHeight = imgHeight + padding * 2

        // Apply aspect ratio
        if let ratio = template.aspectRatio.ratio {
            let currentRatio = canvasWidth / canvasHeight
            if currentRatio > ratio {
                canvasHeight = canvasWidth / ratio
            } else {
                canvasWidth = canvasHeight * ratio
            }
        }

        let canvasSize = CGSize(width: canvasWidth, height: canvasHeight)

        guard let context = CGContext(
            data: nil,
            width: Int(canvasSize.width),
            height: Int(canvasSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let fullRect = CGRect(origin: .zero, size: canvasSize)

        // Draw background
        switch template.type {
        case .gradient(let startColor, let endColor, _):
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [startColor.cgColor, endColor.cgColor] as CFArray,
                locations: [0, 1]
            )!
            context.drawLinearGradient(
                gradient,
                start: .zero,
                end: CGPoint(x: canvasSize.width, y: canvasSize.height),
                options: [.drawsAfterEndLocation, .drawsBeforeStartLocation]
            )

        case .solid(let color):
            context.setFillColor(color.cgColor)
            context.fill(fullRect)

        case .image(let imagePath):
            if let bgImage = NSImage(contentsOfFile: imagePath),
               let cgBg = bgImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                context.draw(cgBg, in: fullRect)
            }
        }

        // Calculate centered image position
        let imgX = (canvasSize.width - imgWidth) / 2
        let imgY = (canvasSize.height - imgHeight) / 2
        let imgRect = CGRect(x: imgX, y: imgY, width: imgWidth, height: imgHeight)

        // Draw shadow
        if template.shadowRadius > 0 {
            context.setShadow(
                offset: CGSize(width: 0, height: -4),
                blur: template.shadowRadius,
                color: NSColor.black.withAlphaComponent(0.4).cgColor
            )
        }

        // Draw rounded rect clipped image
        if template.cornerRadius > 0 {
            let clipPath = CGPath(roundedRect: imgRect, cornerWidth: template.cornerRadius, cornerHeight: template.cornerRadius, transform: nil)
            context.addPath(clipPath)
            context.clip()
        }

        context.draw(image, in: imgRect)

        return context.makeImage()
    }
}
