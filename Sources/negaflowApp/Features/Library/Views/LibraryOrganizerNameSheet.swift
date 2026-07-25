import SwiftUI

struct LibraryOrganizerNameRequest: Identifiable {
    enum Action {
        case createManual(frameIDs: [UUID])
        case createSmart(definition: LibrarySearchDefinition)
        case createSavedSearch(definition: LibrarySearchDefinition)
        case renameManual(id: UUID)
        case renameSmart(id: UUID)
        case renameSavedSearch(id: UUID)
        case renameFolder(url: URL)
    }

    let id = UUID()
    let action: Action
    let title: AppLocalizedPhrase
    let fieldLabel: AppLocalizedPhrase
    var initialName = ""
}

struct LibraryOrganizerNameSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let title: String
    let fieldLabel: String
    let onSave: (String) -> Void
    @State private var name: String

    init(
        title: String,
        fieldLabel: String,
        initialName: String,
        onSave: @escaping (String) -> Void
    ) {
        self.title = title
        self.fieldLabel = fieldLabel
        self.onSave = onSave
        _name = State(initialValue: initialName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.title3.weight(.semibold))
            TextField(fieldLabel, text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            HStack {
                Spacer()
                Button(model.text(AppLocalizedPhrase.cancel)) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(model.text(AppLocalizedPhrase.save), action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        onSave(name)
        dismiss()
    }
}
