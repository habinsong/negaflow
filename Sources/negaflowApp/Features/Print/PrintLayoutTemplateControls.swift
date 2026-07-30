import SwiftUI

struct PrintLayoutTemplateControls: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var settingsStore: PrintWorkspaceSettingsStore
    @State private var selectedTemplateID: UUID?
    @State private var templateName = ""
    @State private var operationFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: PrintInspectorMetrics.verticalSpacing) {
            if !model.printLayoutTemplateStore.templates.isEmpty {
                PrintInspectorStackedField(model.text(.printTemplates)) {
                    PrintInspectorPopupPicker(
                        selection: $selectedTemplateID,
                        options: templateOptions,
                        accessibilityLabel: model.text(.printTemplates)
                    )
                }

                HStack(spacing: 6) {
                    Button(model.text(AppLocalizedPhrase.apply)) {
                        applySelectedTemplate()
                    }
                    .buttonStyle(PrintInspectorTransientButtonStyle())
                    .frame(maxWidth: .infinity)
                    .disabled(selectedTemplate == nil)

                    Button(role: .destructive) {
                        deleteSelectedTemplate()
                    } label: {
                        Text(model.text(AppLocalizedPhrase.delete))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(
                        PrintInspectorTransientButtonStyle(foregroundStyle: .red)
                    )
                    .frame(maxWidth: .infinity)
                    .disabled(selectedTemplate == nil)
                }

                Divider()
            }

            PrintInspectorInlineField(model.text(.printTemplateName)) {
                HStack(spacing: 6) {
                    PrintInspectorTextField(
                        prompt: model.text(.printTemplateName),
                        text: $templateName
                    )
                    .onChange(of: templateName) { _, value in
                        let normalized = String(value.prefix(80))
                        if normalized != value { templateName = normalized }
                    }

                    Button {
                        saveTemplate()
                    } label: {
                        Label(
                            model.text(AppLocalizedPhrase.save),
                            systemImage: "square.and.arrow.down"
                        )
                    }
                    .buttonStyle(PrintInspectorTransientButtonStyle())
                    .disabled(
                        !model.printLayoutTemplateStore.canModify
                            || PrintLayoutTemplate.normalizedName(templateName).isEmpty
                    )
                }
            }

            if operationFailed || !model.printLayoutTemplateStore.canModify {
                PrintInspectorHelpText(
                    text: model.text(.printTemplateUpdateFailed),
                    systemImage: "exclamationmark.triangle.fill",
                    tint: .red
                )
            }
        }
        .accessibilityLabel(model.text(.printTemplates))
    }

    private var selectedTemplate: PrintLayoutTemplate? {
        guard let selectedTemplateID else { return nil }
        return model.printLayoutTemplateStore.templates.first { $0.id == selectedTemplateID }
    }

    private var templateOptions: [PrintInspectorPopupPicker<UUID?>.Option] {
        [.init(nil, title: model.text(.noLook))]
            + model.printLayoutTemplateStore.templates.map {
                .init(Optional($0.id), title: $0.name)
            }
    }

    private func applySelectedTemplate() {
        guard let selectedTemplate else { return }
        settingsStore.apply(selectedTemplate.settings)
        operationFailed = false
    }

    private func saveTemplate() {
        guard let saved = model.printLayoutTemplateStore.add(
            name: templateName,
            settings: settingsStore.templateSettings()
        ) else {
            operationFailed = true
            return
        }
        selectedTemplateID = saved.id
        templateName = ""
        operationFailed = false
    }

    private func deleteSelectedTemplate() {
        guard let selectedTemplateID else { return }
        model.printLayoutTemplateStore.delete(id: selectedTemplateID)
        if model.printLayoutTemplateStore.templates.contains(where: { $0.id == selectedTemplateID }) {
            operationFailed = true
        } else {
            self.selectedTemplateID = nil
            operationFailed = false
        }
    }
}
