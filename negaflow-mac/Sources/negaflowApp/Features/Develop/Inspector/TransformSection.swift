import SwiftUI
import Chromabase

/// 변환(원근) — 모드 캡슐 두 줄, 슬라이더 일곱 개, 자르기 제한.
struct TransformSection: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var frame: ScanFrame

    private static let modeRows: [[PerspectiveMode]] = [[.off, .auto, .guided], [.level, .vertical, .full]]

    var body: some View {
        VStack(spacing: 10) {
            VStack(spacing: 6) {
                ForEach(Self.modeRows, id: \.self) { row in
                    CapsuleSegmented(
                        options: row,
                        label: { modeLabel($0) },
                        selection: modeBinding
                    )
                }
            }

            if correction.mode == .guided {
                Text(model.text(AppLocalizedPhrase.transformGuidedHint))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                if !correction.guides.isEmpty {
                    Button(model.text(AppLocalizedPhrase.transformGuidedClear)) {
                        model.setPerspectiveGuides(frame, guides: [])
                    }
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Divider().opacity(0.4)

            slider(.transformVertical, \.vertical, range: PerspectiveCorrection.sliderRange)
            slider(.transformHorizontal, \.horizontal, range: PerspectiveCorrection.sliderRange)
            slider(.transformRotate, \.rotate, range: PerspectiveCorrection.rotateRange, decimals: 1)
            slider(.transformAspect, \.aspect, range: PerspectiveCorrection.sliderRange)
            slider(.transformScale, \.scale, range: PerspectiveCorrection.scaleRange, neutral: 100, signed: false)
            slider(.transformOffsetX, \.offsetX, range: PerspectiveCorrection.sliderRange, decimals: 1)
            slider(.transformOffsetY, \.offsetY, range: PerspectiveCorrection.sliderRange, decimals: 1)

            Toggle(model.text(AppLocalizedPhrase.transformConstrainCrop), isOn: Binding(
                get: { correction.constrainCrop },
                set: { value in model.updatePerspective(frame) { $0.constrainCrop = value } }
            ))
            .toggleStyle(.checkbox)
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var correction: PerspectiveCorrection { frame.imageTransform.perspective }

    private var modeBinding: Binding<PerspectiveMode> {
        Binding(
            get: { correction.mode },
            set: { model.selectPerspectiveMode(frame, mode: $0) }
        )
    }

    private func modeLabel(_ mode: PerspectiveMode) -> String {
        switch mode {
        case .off: return model.text(AppLocalizedPhrase.transformModeOff)
        case .auto: return model.text(AppLocalizedPhrase.transformModeAuto)
        case .guided: return model.text(AppLocalizedPhrase.transformModeGuided)
        case .level: return model.text(AppLocalizedPhrase.transformModeLevel)
        case .vertical: return model.text(AppLocalizedPhrase.transformModeVertical)
        case .full: return model.text(AppLocalizedPhrase.transformModeFull)
        }
    }

    /// 다른 슬라이더와 같은 모양·같은 동작(두 번 누르면 기본값, 값 칸을 눌러 직접 입력)이다.
    /// 값은 −100…100 같은 정수 눈금이라 소수 둘째 자리 대신 정수(회전·오프셋은 소수 한 자리)로 보인다.
    private func slider(
        _ title: AppLocalizedPhrase,
        _ keyPath: WritableKeyPath<PerspectiveCorrection, Double>,
        range: ClosedRange<Double>,
        neutral: Double = 0,
        decimals: Int = 0,
        signed: Bool = true
    ) -> some View {
        let value = correction[keyPath: keyPath]
        let binding = Binding<Double>(
            get: { correction[keyPath: keyPath] },
            set: { newValue in
                let clamped = min(max(newValue, range.lowerBound), range.upperBound)
                model.updatePerspective(frame) { $0[keyPath: keyPath] = clamped }
            }
        )
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(model.text(title)).font(.caption)
                Spacer()
                EditableSliderValueText(
                    value: value,
                    displayText: Self.valueText(value, neutral: neutral, decimals: decimals, signed: signed),
                    inputRange: range,
                    inputText: { String(format: "%.\(decimals)f", $0) },
                    onCommit: { binding.wrappedValue = $0 }
                )
            }
            ResettableSlider(value: binding, in: range, resetValue: neutral)
        }
    }

    static func valueText(_ value: Double, neutral: Double, decimals: Int, signed: Bool) -> String {
        let step = pow(10, Double(-decimals)) / 2
        if signed {
            return abs(value - neutral) < step
                ? String(format: "%.\(decimals)f", 0.0)
                : String(format: "%+.\(decimals)f", value)
        }
        return String(format: "%.\(decimals)f", value)
    }
}
