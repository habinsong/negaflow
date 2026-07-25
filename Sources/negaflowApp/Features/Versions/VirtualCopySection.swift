import SwiftUI

struct VirtualCopySection: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var frame: ScanFrame

    var body: some View {
        Section {
            TransferButton(
                title: model.text(AppLocalizedPhrase.virtualCopy),
                systemName: "plus.square.on.square",
                help: model.text(AppLocalizedPhrase.virtualCopyHelp)
            ) {
                model.createVirtualCopy(from: frame)
            }
        } header: {
            sectionHeader(model.text(AppLocalizedPhrase.virtualCopy), systemImage: "plus.square.on.square")
        }
    }
}
