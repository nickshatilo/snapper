import AppKit

enum PasteboardHelper {
    /// Copies the image as both TIFF and PNG. `scale` is the source display's
    /// backing scale; it sets the bitmap's point size so retina captures paste
    /// at their on-screen size instead of 2x.
    static func copyImage(_ image: CGImage, scale: CGFloat = 1) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let bitmapRep = NSBitmapImageRep(cgImage: image)
        if scale > 0 {
            bitmapRep.size = NSSize(
                width: CGFloat(image.width) / scale,
                height: CGFloat(image.height) / scale
            )
        }

        // A single pasteboard item carries both representations; setting data
        // on NSPasteboard directly requires the type to have been declared and
        // silently drops it otherwise.
        let item = NSPasteboardItem()
        if let tiffData = bitmapRep.representation(using: .tiff, properties: [:]) {
            item.setData(tiffData, forType: .tiff)
        }
        if let pngData = bitmapRep.representation(using: .png, properties: [:]) {
            item.setData(pngData, forType: .png)
        }
        pasteboard.writeObjects([item])
    }

    static func copyText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    static func copyFile(at url: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
    }
}
