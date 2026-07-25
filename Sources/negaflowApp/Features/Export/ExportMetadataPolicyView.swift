import SwiftUI
import Chromabase

struct ExportMetadataPolicyView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Picker(localized(.label), selection: $model.exportMetadataPolicy) {
            Text(localized(.all)).tag(ExportMetadataPolicy.all)
            Text(localized(.copyrightOnly)).tag(ExportMetadataPolicy.copyrightOnly)
            Text(localized(.removeLocation)).tag(ExportMetadataPolicy.removeLocation)
            Text(localized(.minimal)).tag(ExportMetadataPolicy.minimal)
        }
    }

    private func localized(_ text: ExportMetadataLocalizedText) -> String {
        text.resolved(language: model.appLanguage)
    }
}
