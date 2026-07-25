import SwiftUI

struct LegalNoticeSettingsSection: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Section {
            legalBlock(title: model.text(.legalLicenseTitle), body: model.text(.legalLicenseBody))
            legalBlock(title: model.text(.legalTrademarkTitle), body: model.text(.legalTrademarkBody))
            legalBlock(title: model.text(.legalNamesTitle), body: model.text(.legalNamesBody))
            legalBlock(title: model.text(.legalProfilesTitle), body: model.text(.legalProfilesBody))
            legalBlock(title: model.text(.legalAffiliationTitle), body: model.text(.legalAffiliationBody))
        } header: {
            sectionHeader(model.text(.settingsLegalTab), systemImage: "doc.text.magnifyingglass")
        }
    }

    private func legalBlock(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.callout.weight(.semibold))
            Text(body)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(.vertical, 4)
    }
}
