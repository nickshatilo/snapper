import SwiftUI

struct ToolbarView: View {
    @Bindable var toolManager: ToolManager
    @State private var hoveredGroup: PrimaryToolGroup?

    var body: some View {
        VStack(spacing: 2) {
            ForEach(PrimaryToolGroup.allCases, id: \.self) { group in
                toolButton(group)
            }
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }

    private func toolButton(_ group: PrimaryToolGroup) -> some View {
        let isSelected = toolManager.currentTool.primaryGroup == group
        let isHovered = hoveredGroup == group

        return Button(action: {
            if !isSelected {
                toolManager.currentTool = ToolType.defaultTool(for: group)
            }
        }) {
            Image(systemName: group.iconName)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 32, height: 32)
                .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(isHovered ? 0.95 : 0.75))
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: isSelected
                                    ? [Color.accentColor.opacity(0.95), Color.accentColor.opacity(0.70)]
                                    : [Color.primary.opacity(isHovered ? 0.12 : 0.08), Color.primary.opacity(isHovered ? 0.05 : 0.03)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .overlay {
                    if isHovered && !isSelected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1)
                    }
                }
                .shadow(color: isSelected ? Color.accentColor.opacity(0.35) : .clear, radius: 5, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .help(group.displayName)
        .onHover { hovering in
            if hovering {
                hoveredGroup = group
            } else if hoveredGroup == group {
                hoveredGroup = nil
            }
        }
    }
}
