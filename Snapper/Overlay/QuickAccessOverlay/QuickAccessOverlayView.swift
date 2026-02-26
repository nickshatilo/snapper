import SwiftUI

struct QuickAccessOverlayView: View {
    let manager: QuickAccessManager
    let thumbnailWidth: CGFloat

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .trailing, spacing: 8) {
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
        .frame(maxHeight: .infinity, alignment: .topTrailing)
        .animation(.interactiveSpring(response: 0.38, dampingFraction: 0.9, blendDuration: 0.1), value: manager.captures.map(\.id))
        .scrollIndicators(.never)
        .background(Color.clear)
    }
}
