import SwiftUI
import Chromabase

struct ToneCurvePointFields: View {
    @EnvironmentObject private var model: AppModel
    @Binding var points: [CurvePoint]
    @Binding var selectedIndex: Int?
    let onChange: () -> Void

    var body: some View {
        if let index = selectedIndex, points.indices.contains(index) {
            HStack(spacing: 8) {
                percentageField(
                    label: model.accessibilityText(.input),
                    value: inputBinding(index),
                    disabled: index == 0 || index == points.count - 1
                )
                percentageField(
                    label: model.accessibilityText(.output),
                    value: outputBinding(index),
                    disabled: false
                )
                Spacer(minLength: 0)
            }
        }
    }

    private func percentageField(
        label: String,
        value: Binding<Double>,
        disabled: Bool
    ) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            TextField(label, value: value, format: .number.precision(.fractionLength(0)))
                .frame(width: 48)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .disabled(disabled)
            Text("%").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func inputBinding(_ index: Int) -> Binding<Double> {
        Binding(
            get: { points[index].x * 100 },
            set: { percentage in
                guard index > 0, index < points.count - 1 else { return }
                let x = min(max(percentage / 100, points[index - 1].x + 0.01), points[index + 1].x - 0.01)
                points[index] = CurvePoint(x: x, y: points[index].y)
                onChange()
            }
        )
    }

    private func outputBinding(_ index: Int) -> Binding<Double> {
        Binding(
            get: { points[index].y * 100 },
            set: { percentage in
                points[index] = CurvePoint(x: points[index].x, y: min(max(percentage / 100, 0), 1))
                onChange()
            }
        )
    }
}
