import SwiftUI

struct LibraryBackupGenerationRow: View {
    @EnvironmentObject private var model: AppModel
    let generation: LibraryBackupGeneration

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: stateIcon)
                .foregroundStyle(generation.state.isRestorable ? .secondary : .tertiary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(dateText)
                Text(model.text(
                    AppLocalizedPhrase.libraryBackupCountsFormat,
                    generation.frameCount ?? 0,
                    generation.defectRecipeCount ?? 0
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(stateText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("negaflow.recovery.generation")
        .accessibilityValue(generation.state.rawValue)
    }

    private var dateText: String {
        guard let date = generation.createdAt else {
            return model.text(AppLocalizedPhrase.libraryBackupUnknownDate)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: model.appLanguage.resolved.rawValue)
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private var stateText: String {
        switch generation.state {
        case .checksummed:
            model.text(AppLocalizedPhrase.libraryBackupChecksummed)
        case .legacyStructureOnly:
            model.text(AppLocalizedPhrase.libraryBackupLegacy)
        case .incompatible:
            model.text(AppLocalizedPhrase.libraryBackupIncompatible)
        case .damaged:
            model.text(AppLocalizedPhrase.libraryBackupDamaged)
        }
    }

    private var stateIcon: String {
        switch generation.state {
        case .checksummed: "checkmark.seal"
        case .legacyStructureOnly: "clock.arrow.circlepath"
        case .incompatible: "nosign"
        case .damaged: "exclamationmark.triangle"
        }
    }
}
