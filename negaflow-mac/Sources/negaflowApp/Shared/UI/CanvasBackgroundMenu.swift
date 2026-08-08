import SwiftUI

struct CanvasBackgroundMenu: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Section {
            Picker(
                selection: Binding(
                    get: { model.canvasBackground },
                    set: { model.canvasBackground = $0 }
                )
            ) {
                ForEach(CanvasBackground.allCases) { background in
                    Text(background.label(language: model.appLanguage))
                        .tag(background)
                }
            } label: {
                EmptyView()
            }
            .labelsHidden()
            .pickerStyle(.inline)
        } header: {
            Text(model.text(AppLocalizedPhrase.canvasBackgroundMenu))
        }
    }
}
