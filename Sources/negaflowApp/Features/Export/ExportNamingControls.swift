import SwiftUI

struct ExportNamingControls: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 6) {
            TextField(localized(.pattern), text: $model.exportNamingTemplate)
            Menu {
                Section(localized(.namingOptions)) {
                    Button(localized(.photoName)) {
                        model.exportNamingTemplate = ExportNamingTemplate.defaultPattern
                    }
                    Button(localized(.photoNameSequence)) {
                        model.exportNamingTemplate = ExportNamingTemplate.photoNameSequencePattern
                    }
                    Button(localized(.sequenceOnly)) {
                        model.exportNamingTemplate = ExportNamingTemplate.sequenceOnlyPattern
                    }
                }
                Section(localized(.tokens)) {
                    ForEach(ExportNamingTemplate.tokens, id: \.self) { token in
                        Button {
                            model.exportNamingTemplate += "{\(token)}"
                        } label: {
                            Text(verbatim: "{\(token)}")
                        }
                    }
                }
            } label: {
                Image(systemName: "plus")
            }
            .menuStyle(.borderlessButton)
            .help(localized(.namingOptions))
        }
        if ExportNamingTemplate.usesSequence(model.exportNamingTemplate) {
            LabeledContent(localized(.sequenceStart)) {
                TextField(
                    localized(.sequenceStart),
                    value: $model.exportSequenceStart,
                    format: .number
                )
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 72)
            }
        }
        LabeledContent(localized(.preview)) {
            Text(model.exportNamingPreview() ?? "—")
                .foregroundStyle(
                    ExportNamingTemplate.isValid(model.exportNamingTemplate)
                        ? Color.secondary
                        : Color.red
                )
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func localized(_ text: ExportNamingLocalizedText) -> String {
        text.resolved(language: model.appLanguage)
    }
}
