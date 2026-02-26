import AppKit

final class ImageWrapper: NSObject {
    let image: CGImage

    init(_ image: CGImage) {
        self.image = image
    }
}
