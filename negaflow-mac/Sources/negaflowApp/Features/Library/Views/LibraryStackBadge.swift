import SwiftUI

struct LibraryStackBadge: View {
    @EnvironmentObject private var model: AppModel
    let stack: LibraryPhotoStack

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: stack.isCollapsed ? "rectangle.stack.fill" : "rectangle.stack")
            Text(stack.frameIDs.count, format: .number)
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .foregroundStyle(.white)
        .background(.black.opacity(0.72), in: Capsule())
        .help(model.stackText(.count, stack.frameIDs.count))
        .accessibilityLabel(model.stackText(.count, stack.frameIDs.count))
    }
}
