import AppKit

enum PasteboardHelper {
    static func copyImage(_ image: CGImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))

        // Write as both TIFF and PNG for maximum compatibility
        pasteboard.writeObjects([nsImage])

        if let pngData = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
            pasteboard.setData(pngData, forType: .png)
        }
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
