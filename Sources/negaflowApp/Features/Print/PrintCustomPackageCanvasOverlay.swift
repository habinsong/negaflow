import Chromabase
import SwiftUI

struct PrintCustomPackageCanvasOverlay: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var settingsStore: PrintWorkspaceSettingsStore
    let package: PrintPackageSettings
    let page: PrintPackagePageLayout
    let paperRect: CGRect
    let scale: CGFloat
    @Binding var selectedItemIndex: Int?
    @State private var movingItemIndex: Int?
    @State private var moveStartRect: CGRect?
    @State private var resizingItemIndex: Int?
    @State private var resizeStartRect: CGRect?

    var body: some View {
        ForEach(Array(customItemIndices.enumerated()), id: \.element) { itemOffset, definitionIndex in
            if page.items.indices.contains(itemOffset) {
                let cellRect = converted(page.items[itemOffset].cellRectPoints)
                let isSelected = selectedItemIndex == definitionIndex
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .overlay {
                        Rectangle()
                            .stroke(
                                isSelected ? Color.accentColor : Color.clear,
                                style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])
                            )
                    }
                    .frame(width: cellRect.width, height: cellRect.height)
                    .position(x: cellRect.midX, y: cellRect.midY)
                    .onTapGesture { selectedItemIndex = definitionIndex }
                    .gesture(moveGesture(index: definitionIndex))
                    .accessibilityLabel("\(model.text(.printCell)) \(definitionIndex + 1)")
                    .zIndex(2_000 + Double(page.items[itemOffset].zIndex))

                if isSelected {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor)
                        .frame(width: 10, height: 10)
                        .position(x: cellRect.maxX, y: cellRect.maxY)
                        .gesture(resizeGesture(index: definitionIndex))
                        .accessibilityHidden(true)
                        .zIndex(4_000 + Double(page.items[itemOffset].zIndex))
                }
            }
        }
    }

    private var customItemIndices: [Int] {
        package.customItems.indices
            .filter { package.customItems[$0].pageIndex == page.pageIndex }
            .sorted { lhs, rhs in
                let left = package.customItems[lhs]
                let right = package.customItems[rhs]
                return left.zIndex == right.zIndex ? lhs < rhs : left.zIndex < right.zIndex
            }
    }

    private func moveGesture(index: Int) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                selectedItemIndex = index
                if movingItemIndex != index {
                    movingItemIndex = index
                    moveStartRect = storedRect(index: index)
                }
                guard let start = moveStartRect,
                      page.contentRectPoints.width > 0,
                      page.contentRectPoints.height > 0 else { return }
                let deltaX = value.translation.width / (page.contentRectPoints.width * scale)
                let deltaY = -value.translation.height / (page.contentRectPoints.height * scale)
                updateRect(index: index) { rect in
                    rect.origin.x = min(max(start.minX + deltaX, 0), 1 - start.width)
                    rect.origin.y = min(max(start.minY + deltaY, 0), 1 - start.height)
                }
            }
            .onEnded { _ in
                movingItemIndex = nil
                moveStartRect = nil
            }
    }

    private func resizeGesture(index: Int) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                selectedItemIndex = index
                if resizingItemIndex != index {
                    resizingItemIndex = index
                    resizeStartRect = storedRect(index: index)
                }
                guard let start = resizeStartRect,
                      page.contentRectPoints.width > 0,
                      page.contentRectPoints.height > 0 else { return }
                let deltaWidth = value.translation.width / (page.contentRectPoints.width * scale)
                let deltaHeight = value.translation.height / (page.contentRectPoints.height * scale)
                let maximumY = start.maxY
                updateRect(index: index) { rect in
                    rect.size.width = min(max(start.width + deltaWidth, 0.02), 1 - start.minX)
                    rect.size.height = min(max(start.height + deltaHeight, 0.02), maximumY)
                    rect.origin.y = maximumY - rect.height
                }
            }
            .onEnded { _ in
                resizingItemIndex = nil
                resizeStartRect = nil
            }
    }

    private func storedRect(index: Int) -> CGRect? {
        guard settingsStore.packageSettings.customItems.indices.contains(index) else { return nil }
        return settingsStore.packageSettings.customItems[index].normalizedRect
    }

    private func updateRect(index: Int, update: (inout CGRect) -> Void) {
        var settings = settingsStore.packageSettings
        guard settings.customItems.indices.contains(index) else { return }
        var rect = settings.customItems[index].normalizedRect
        update(&rect)
        settings.customItems[index].normalizedRect = rect
        settingsStore.packageSettings = settings
    }

    private func converted(_ rect: CGRect) -> CGRect {
        CGRect(
            x: paperRect.minX + rect.minX * scale,
            y: paperRect.minY + (page.canvasSizePoints.height - rect.maxY) * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }
}
