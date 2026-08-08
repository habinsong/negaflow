import SwiftUI

struct FrameRenameSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var frame: ScanFrame
    @State private var numberText: String

    init(frame: ScanFrame) {
        self.frame = frame
        _numberText = State(initialValue: String(frame.presentationIndex))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.text(AppLocalizedPhrase.renamePhoto))
                .font(.headline)
            TextField(model.text(AppLocalizedPhrase.photoName), text: $numberText)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("negaflow.photo-number-field")
                .onChange(of: numberText) { _, value in
                    let digits = value.filter(\.isNumber)
                    if digits != value { numberText = digits }
                }
                .onSubmit(commit)
            HStack {
                Spacer()
                Button(model.text(AppLocalizedPhrase.cancel)) {
                    dismiss()
                }
                Button(model.text(AppLocalizedPhrase.rename)) {
                    commit()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canCommit)
            }
        }
        .padding(20)
        .frame(width: 340)
    }

    private var requestedNumber: Int? {
        guard let number = Int(numberText), number > 0 else { return nil }
        return number
    }

    private var canCommit: Bool {
        guard let requestedNumber else { return false }
        return model.isPhotoNumberAvailable(requestedNumber, for: frame)
    }

    private func commit() {
        guard let requestedNumber,
              model.renamePhotoNumber(requestedNumber, for: frame) else {
            return
        }
        dismiss()
    }
}
