import SwiftUI
import AppKit
import Chromabase

struct InspectorSlider: View {
    @EnvironmentObject private var model: AppModel
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let focusID: InspectorSliderFocus?
    let focusedSlider: FocusState<InspectorSliderFocus?>.Binding?
    let doubleClickResetValue: Double?

    init(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        focusID: InspectorSliderFocus? = nil,
        focusedSlider: FocusState<InspectorSliderFocus?>.Binding? = nil,
        doubleClickResetValue: Double? = 0
    ) {
        self.title = title
        self._value = value
        self.range = range
        self.focusID = focusID
        self.focusedSlider = focusedSlider
        self.doubleClickResetValue = doubleClickResetValue
    }

    @ViewBuilder
    var body: some View {
        if let focusID, let focusedSlider {
            sliderContent
                .focusable(true)
                .focusEffectDisabled()
                .focused(focusedSlider, equals: focusID)
                .onTapGesture { focusedSlider.wrappedValue = focusID }
                .help(model.text(AppLocalizedPhrase.sliderKeyboardHelp))
        } else {
            sliderContent
        }
    }

    private var sliderContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption)
                Spacer()
                EditableSliderValueText(
                    value: value,
                    displayText: signedControlText(value),
                    inputRange: range,
                    onCommit: { value = $0 }
                )
            }
            ResettableSlider(value: $value, in: range, resetValue: doubleClickResetValue)
        }
        .padding(.vertical, focusID == nil ? 0 : 2)
        .padding(.horizontal, focusID == nil ? 0 : 4)
    }
}
