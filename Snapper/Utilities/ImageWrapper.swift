import AppKit

final class ImageWrapper: NSObject {
    let image: CGImage
    /// Backing scale of the image's source display (1 when unknown).
    let scale: CGFloat

    init(_ image: CGImage, scale: CGFloat = 1) {
        self.image = image
        self.scale = scale
    }
}
