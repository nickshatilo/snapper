import SwiftUI

struct QuickAccessOverlayView: View {
    let manager: QuickAccessManager
    let thumbnailWidth: CGFloat

    var body: some View {
        ScrollView {
            VStack(alignment: .trailing, spacing: 8) {
                ForEach(manager.captures) { capture in
                    CaptureThumbnailView(
                        capture: capture,
                        manager: manager,
                        thumbnailWidth: thumbnailWidth - 8
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .topTrailing)
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
        }
        .frame(width: thumbnailWidth)
        .scrollIndicators(.never)
        .background(Color.clear)
    }
}
