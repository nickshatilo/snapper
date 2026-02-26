import AppKit

struct CaptureResult {
    let image: CGImage
    let mode: CaptureMode
    let timestamp: Date
    let sourceRect: CGRect
    let windowName: String?
    let applicationName: String?

    var width: Int { image.width }
    var height: Int { image.height }

    var nsImage: NSImage {
        NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}
