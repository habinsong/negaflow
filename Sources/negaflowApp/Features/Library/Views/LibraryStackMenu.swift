import SwiftUI

struct LibraryStackMenu: View {
    @EnvironmentObject private var model: AppModel
    let frame: ScanFrame
    let orderedFrameIDs: [UUID]

    var body: some View {
        if let stack = model.stack(containing: frame.id) {
            Button(stack.isCollapsed ? model.stackText(.expand) : model.stackText(.collapse)) {
                _ = model.toggleStackCollapsed(id: stack.id)
            }
            Button(model.stackText(.ungroup)) {
                _ = model.ungroupStack(id: stack.id)
            }
        } else if selectedFrameIDs.count >= 2 {
            Button(model.stackText(.group)) {
                _ = model.createStack(frameIDs: selectedFrameIDs)
            }
        }
    }

    private var selectedFrameIDs: [UUID] {
        let selected = model.selectedFrameIDs
        if !selected.contains(frame.id) { return [frame.id] }
        return orderedFrameIDs.filter(selected.contains)
    }
}
