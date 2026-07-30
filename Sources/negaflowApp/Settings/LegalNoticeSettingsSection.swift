import SwiftUI

struct LegalNoticeSettingsSection: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            legalSection(
                title: model.text(.legalLicenseTitle),
                notice: model.text(.legalLicenseBody)
            )
            legalSection(
                title: model.text(.legalTrademarkTitle),
                notice: model.text(.legalTrademarkBody)
            )
            legalSection(
                title: model.text(.legalNamesTitle),
                notice: model.text(.legalNamesBody)
            )
            legalSection(
                title: model.text(.legalProfilesTitle),
                notice: model.text(.legalProfilesBody)
            )
            legalSection(
                title: model.text(.legalAffiliationTitle),
                notice: model.text(.legalAffiliationBody)
            )
        }
    }

    /// 고지문은 항목마다 그룹을 나눈다 — 한 그룹에 다섯 덩어리를 쌓으면 읽을 곳을 못 찾는다.
    private func legalSection(title: String, notice: String) -> some View {
        AppSettingsSection(title: title) {
            Text(notice)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
