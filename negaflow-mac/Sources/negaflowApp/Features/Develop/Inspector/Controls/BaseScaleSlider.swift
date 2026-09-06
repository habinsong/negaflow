import SwiftUI
import Chromabase

struct BaseScaleSlider: View {
    let title: String
    let ownerID: UUID
    @Binding var value: Double
    @State private var draft: Double?

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(title).font(.caption)
                Spacer()
                EditableSliderValueText(value: draft ?? value,
                    displayText: percentControlText(draft ?? value), inputRange: 50...150,
                    inputText: { percentInputText($0) }, onCommit: { value = $0 / 100 })
            }
            CommitSlider(value: draft ?? value, range: FilmBaseScale.range, step: 0.01,
                resetValue: 1, ownerID: ownerID, label: title,
                onDraft: { draft = $0 }, onCommit: { value = $0 })
                .frame(height: 20)
        }
        .transaction { $0.animation = nil }
        .onDisappear { draft = nil }
    }
}
