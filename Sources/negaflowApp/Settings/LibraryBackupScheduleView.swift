import SwiftUI

struct LibraryBackupScheduleView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var store: LibraryBackupScheduleStore

    var body: some View {
        Group {
            AppSettingsRow(localized(.schedule)) {
                Picker(String(), selection: $store.schedule) {
                    ForEach(LibraryBackupSchedule.allCases, id: \.self) { schedule in
                        Text(scheduleName(schedule)).tag(schedule)
                    }
                }
                .labelsHidden()
            }

            AppSettingsValueRow(
                label: localized(.lastAttempt),
                value: dateText(store.lastAttemptAt)
            )
            AppSettingsValueRow(
                label: localized(.lastSuccess),
                value: dateText(store.lastSuccessAt)
            )

            AppSettingsRow(localized(.verification)) {
                if let drill = store.lastRestoreDrill {
                    VStack(alignment: .trailing, spacing: 1) {
                        Label(
                            localized(drill.succeeded ? .passed : .failed),
                            systemImage: drill.succeeded ? "checkmark.seal.fill" : "xmark.octagon.fill"
                        )
                        .foregroundStyle(drill.succeeded ? .green : .red)
                        Text("\(localized(.generation))  \(drill.generationID)")
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                } else {
                    Text(localized(.never))
                }
            }
        }
    }

    private func scheduleName(_ schedule: LibraryBackupSchedule) -> String {
        switch schedule {
        case .manual: localized(.manual)
        case .onTermination: localized(.termination)
        case .daily: localized(.daily)
        case .weekly: localized(.weekly)
        }
    }

    private func dateText(_ date: Date?) -> String {
        guard let date else { return localized(.never) }
        return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
    }

    private func localized(_ text: BackupScheduleLocalizedText) -> String {
        text.resolved(language: model.appLanguage)
    }
}
