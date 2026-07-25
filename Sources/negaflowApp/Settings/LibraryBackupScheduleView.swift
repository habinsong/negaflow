import SwiftUI

struct LibraryBackupScheduleView: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var store: LibraryBackupScheduleStore

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Picker(localized(.schedule), selection: $store.schedule) {
                ForEach(LibraryBackupSchedule.allCases, id: \.self) { schedule in
                    Text(scheduleName(schedule)).tag(schedule)
                }
            }
            LabeledContent(localized(.lastAttempt)) { Text(dateText(store.lastAttemptAt)) }
            LabeledContent(localized(.lastSuccess)) { Text(dateText(store.lastSuccessAt)) }
            LabeledContent(localized(.verification)) {
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
        .font(.caption)
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
