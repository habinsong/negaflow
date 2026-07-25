import SwiftUI

struct PrintLayoutTemplateControls: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var settingsStore: PrintWorkspaceSettingsStore
    @State private var selectedTemplateID: UUID?
    @State private var templateName = ""
    @State private var operationFailed = false
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                if !model.printLayoutTemplateStore.templates.isEmpty {
                    Picker(model.text(.printTemplates), selection: $selectedTemplateID) {
                        Text(model.text(.noLook)).tag(UUID?.none)
                        ForEach(model.printLayoutTemplateStore.templates) { template in
                            Text(template.name).tag(Optional(template.id))
                        }
                    }
                    HStack(spacing: 12) {
                        Button(model.text(AppLocalizedPhrase.apply)) {
                            applySelectedTemplate()
                        }
                        .disabled(selectedTemplate == nil)
                        Button(role: .destructive) {
                            deleteSelectedTemplate()
                        } label: {
                            Text(model.text(AppLocalizedPhrase.delete))
                        }
                        .disabled(selectedTemplate == nil)
                    }
                }

                HStack(spacing: 8) {
                    TextField(model.text(.printTemplateName), text: $templateName)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: templateName) { _, value in
                            let normalized = String(value.prefix(80))
                            if normalized != value { templateName = normalized }
                        }
                    Button(model.text(AppLocalizedPhrase.save)) {
                        saveTemplate()
                    }
                    .disabled(
                        !model.printLayoutTemplateStore.canModify
                            || PrintLayoutTemplate.normalizedName(templateName).isEmpty
                    )
                }

                if operationFailed || !model.printLayoutTemplateStore.canModify {
                    Text(model.text(.printTemplateUpdateFailed))
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
            .padding(.top, 6)
        } label: {
            Button {
                withAnimation(.snappy(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                Text(model.text(.printTemplates))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.text(.printTemplates))
        }
    }

    private var selectedTemplate: PrintLayoutTemplate? {
        guard let selectedTemplateID else { return nil }
        return model.printLayoutTemplateStore.templates.first { $0.id == selectedTemplateID }
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
