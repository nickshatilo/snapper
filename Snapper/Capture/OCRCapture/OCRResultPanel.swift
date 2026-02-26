import AppKit
import SwiftUI

final class OCRResultPanel {
    private static var panel: NSPanel?

    static func show(text: String) {
        let view = OCRResultView(text: text)
        let hostingView = NSHostingView(rootView: view)

        let newPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        newPanel.title = "OCR Result"
        newPanel.contentView = hostingView
        newPanel.center()
        newPanel.level = .floating
        newPanel.hidesOnDeactivate = false
        newPanel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        panel = newPanel
    }
}

struct OCRResultView: View {
    @State var text: String

    var body: some View {
        VStack(spacing: 12) {
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                Text("\(text.count) characters")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Copy") {
                    PasteboardHelper.copyText(text)
                }
                .buttonStyle(.borderedProminent)

                Button("Save...") {
                    let panel = NSSavePanel()
                    panel.allowedContentTypes = [.plainText]
                    panel.nameFieldStringValue = "OCR Text.txt"
                    if panel.runModal() == .OK, let url = panel.url {
                        try? text.write(to: url, atomically: true, encoding: .utf8)
                    }
                }
            }
        }
        .padding()
    }
}
