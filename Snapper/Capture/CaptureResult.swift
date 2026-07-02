import AppKit

struct CaptureResult {
    let image: CGImage
    let mode: CaptureMode
    let timestamp: Date
    let sourceRect: CGRect
    let windowName: String?
    let applicationName: String?
    /// Backing scale of the source display (2 for retina captures); used to
    /// size NSImages in points so pastes/pins aren't double-sized.
    let scale: CGFloat

    var width: Int { image.width }
    var height: Int { image.height }

    var nsImage: NSImage {
        NSImage(
            cgImage: image,
            size: NSSize(
                width: CGFloat(image.width) / scale,
                height: CGFloat(image.height) / scale
            )
        )
    }
}
