import SwiftUI
import Chromabase

struct OutputSharpeningOptionsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if model.exportFormat != .rawScanTIFF {
            LabeledContent(localized(.amount)) {
                HStack(spacing: 8) {
                    Slider(value: $model.exportOutputSharpening, in: 0...1, step: 0.01)
                    Text(verbatim: "\(Int((model.exportOutputSharpening * 100).rounded()))%")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
            }
            Picker(localized(.medium), selection: $model.exportOutputSharpeningMedium) {
                Text(localized(.screen)).tag(OutputSharpeningMedium.screen)
                Text(localized(.mattePaper)).tag(OutputSharpeningMedium.mattePaper)
                Text(localized(.glossyPaper)).tag(OutputSharpeningMedium.glossyPaper)
            }
            .disabled(model.exportOutputSharpening == 0)
        }
    }

    private func localized(_ text: OutputSharpeningLocalizedText) -> String {
        text.resolved(language: model.appLanguage)
    }
}
