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
    /// 0...1 값을 퍼센트로 보여주고 퍼센트로 입력받는다.
    let showsPercent: Bool

    init(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        focusID: InspectorSliderFocus? = nil,
        focusedSlider: FocusState<InspectorSliderFocus?>.Binding? = nil,
        doubleClickResetValue: Double? = 0,
        showsPercent: Bool = false
    ) {
        self.title = title
        self._value = value
        self.range = range
        self.focusID = focusID
        self.focusedSlider = focusedSlider
        self.doubleClickResetValue = doubleClickResetValue
        self.showsPercent = showsPercent
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
                if showsPercent {
                    EditableSliderValueText(
                        value: value,
                        displayText: percentControlText(value),
                        inputRange: (range.lowerBound * 100)...(range.upperBound * 100),
                        inputText: { percentInputText($0) },
                        onCommit: { value = $0 / 100 }
                    )
                } else {
                    EditableSliderValueText(
                        value: value,
                        displayText: signedControlText(value),
                        inputRange: range,
                        onCommit: { value = $0 }
                    )
                }
            }
            ResettableSlider(value: $value, in: range, resetValue: doubleClickResetValue)
        }
        .padding(.vertical, focusID == nil ? 0 : 2)
        .padding(.horizontal, focusID == nil ? 0 : 4)
    }
}
