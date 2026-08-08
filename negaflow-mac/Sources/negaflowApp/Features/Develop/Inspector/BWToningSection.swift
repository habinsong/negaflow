import SwiftUI
import Chromabase

struct BWToningSection: View {
    @EnvironmentObject private var model: AppModel
    @Binding var toning: BWToning
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            InspectorRow(model.text(AppLocalizedPhrase.mode)) {
                Picker(model.text(AppLocalizedPhrase.mode), selection: modeBinding) {
                    ForEach(BWToningMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 150)
            }

            if toning.mode != .none {
                InspectorSlider(model.text(AppLocalizedPhrase.strength), value: strengthBinding, range: 0...1)
                hueSlider(model.text(AppLocalizedPhrase.shadowHue), value: shadowHueBinding)
                hueSlider(model.text(AppLocalizedPhrase.highlightHue), value: highlightHueBinding)
            }
        }
    }

    private var modeBinding: Binding<BWToningMode> {
        Binding(
            get: { toning.mode },
            set: { mode in
                if mode == .none {
                    toning = BWToning()
                } else {
                    let existingStrength = toning.clampedStrength
                    toning = BWToning(mode: mode, strength: max(existingStrength, 0.45))
                }
                onChange()
            }
        )
    }

    private var strengthBinding: Binding<Double> {
        Binding(
            get: { toning.clampedStrength },
            set: { value in
                toning.strength = value
                onChange()
            }
        )
    }

    private var shadowHueBinding: Binding<Double> {
        Binding(
            get: { normalizedHue(toning.shadowHue) },
            set: { value in
                toning.shadowHue = normalizedHue(value)
                onChange()
            }
        )
    }

    private var highlightHueBinding: Binding<Double> {
        Binding(
            get: { normalizedHue(toning.highlightHue) },
            set: { value in
                toning.highlightHue = normalizedHue(value)
                onChange()
            }
        )
    }

    private func hueSlider(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption)
                Spacer()
                EditableSliderValueText(
                    value: value.wrappedValue,
                    displayText: "\(Int(value.wrappedValue.rounded()))°",
                    inputRange: 0...360,
                    inputText: { String(format: "%.0f", $0) },
                    width: 42,
                    onCommit: { value.wrappedValue = $0 }
                )
            }
            ResettableSlider(value: value, in: 0...360, resetValue: 0)
        }
    }

    private func normalizedHue(_ hue: Double) -> Double {
        let value = hue.truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }
}
