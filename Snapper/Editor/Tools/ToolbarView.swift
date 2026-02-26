import SwiftUI

struct ToolbarView: View {
    @Bindable var toolManager: ToolManager

    var body: some View {
        VStack(spacing: 2) {
            ForEach(ToolType.allCases, id: \.self) { tool in
                toolButton(tool)
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }

    private func toolButton(_ tool: ToolType) -> some View {
        Button(action: { toolManager.currentTool = tool }) {
            Image(systemName: tool.iconName)
                .font(.system(size: 14))
                .frame(width: 32, height: 32)
                .background(toolManager.currentTool == tool ? Color.accentColor.opacity(0.3) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help("\(tool.displayName) (\(tool.shortcutKey))")
    }
}
