import SwiftUI

struct VirtualCopySection: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var frame: ScanFrame

    var body: some View {
        Section {
            TransferButton(
                title: "Virtual Copy",
                systemName: "plus.square.on.square",
                help: "현재 프레임을 raw 공유 비파괴 copy로 생성"
            ) {
                model.createVirtualCopy(from: frame)
            }
        } header: {
            sectionHeader("Virtual Copy", systemImage: "plus.square.on.square")
        }
    }
}
