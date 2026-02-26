import SwiftUI

struct AllInOneHUDView: View {
    let onDismiss: () -> Void
    @State private var selectedMode: CaptureMode = .area
    @State private var timerSeconds: Int = 0

    private let modes: [(CaptureMode, String)] = [
        (.fullscreen, "rectangle.dashed"),
        (.area, "crop"),
        (.window, "macwindow"),
        (.scrolling, "scroll"),
        (.ocr, "text.viewfinder"),
    ]

    var body: some View {
        HStack(spacing: 16) {
            ForEach(modes, id: \.0) { mode, icon in
                Button(action: { selectedMode = mode }) {
                    VStack(spacing: 4) {
                        Image(systemName: icon)
                            .font(.system(size: 20))
                        Text(mode.displayName)
                            .font(.caption2)
                    }
                    .frame(width: 60, height: 52)
                    .background(selectedMode == mode ? Color.accentColor.opacity(0.3) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }

            Divider()
                .frame(height: 40)

            // Timer option
            Picker("", selection: $timerSeconds) {
                Text("No Timer").tag(0)
                Text("3s").tag(3)
                Text("5s").tag(5)
                Text("10s").tag(10)
            }
            .frame(width: 90)

            // Capture button
            Button(action: capture) {
                Text("Capture")
                    .fontWeight(.medium)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func capture() {
        onDismiss()

        if timerSeconds > 0 {
            NotificationCenter.default.post(
                name: .startTimerCapture,
                object: TimerCaptureRequest(seconds: timerSeconds, mode: selectedMode)
            )
        } else {
            NotificationCenter.default.post(name: .startCapture, object: selectedMode)
        }
    }
}
