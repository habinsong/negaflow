import SwiftUI
import Chromabase

/// 색보정(Color Grading) — 어두운/중간/밝은 영역 캡슐 + 색상환(색조·채도) + 광도 슬라이더,
/// 전역 혼합(blending)/균형(balance) 슬라이더.
struct ColorGradingSection: View {
    @EnvironmentObject private var model: AppModel
    @Binding var grading: ColorGrading
    let onChange: () -> Void
    @State private var region: Region = .midtones

    enum Region: String, CaseIterable, Identifiable {
        case shadows, midtones, highlights
        var id: Self { self }
        func label(language: AppLanguage) -> String {
            switch self {
            case .shadows: return AppLocalization.text(AppLocalizedPhrase.shadows, language: language)
            case .midtones: return AppLocalization.text(AppLocalizedPhrase.midtones, language: language)
            case .highlights: return AppLocalization.text(AppLocalizedPhrase.highlights, language: language)
            }
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            CapsuleSegmented(options: Region.allCases, label: { $0.label(language: model.appLanguage) }, selection: $region)

            ColorWheelView(hue: hueBinding, saturation: satBinding, onChange: onChange)
                .frame(maxWidth: .infinity)

            HStack {
                Text(model.text(AppLocalizedPhrase.hue)).font(.caption).frame(width: 64, alignment: .leading)
                Text("\(Int(regionValue.hue.rounded()))°")
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                Text(model.text(AppLocalizedPhrase.saturationAbbrev)).font(.caption)
                Text(String(format: "%.0f%%", regionValue.saturation * 100))
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }

            labeledSlider(model.text(AppLocalizedPhrase.luminance), lumBinding, range: -1...1)

            Divider().opacity(0.4)

            labeledSlider(model.text(AppLocalizedPhrase.blending), blendingBinding, range: 0...1)
            labeledSlider(model.text(AppLocalizedPhrase.balance), balanceBinding, range: -1...1)
        }
    }

    private var regionKeyPath: WritableKeyPath<ColorGrading, ColorGradeRegion> {
        switch region {
        case .shadows: return \.shadows
        case .midtones: return \.midtones
        case .highlights: return \.highlights
        }
    }

    private var regionValue: ColorGradeRegion { grading[keyPath: regionKeyPath] }

    private var hueBinding: Binding<Double> {
        Binding(get: { grading[keyPath: regionKeyPath].hue },
                set: { grading[keyPath: regionKeyPath].hue = $0 })
    }
    private var satBinding: Binding<Double> {
        Binding(get: { grading[keyPath: regionKeyPath].saturation },
                set: { grading[keyPath: regionKeyPath].saturation = $0 })
    }
    private var lumBinding: Binding<Double> {
        Binding(get: { grading[keyPath: regionKeyPath].luminance },
                set: { grading[keyPath: regionKeyPath].luminance = $0; onChange() })
    }
    private var blendingBinding: Binding<Double> {
        Binding(get: { grading.blending }, set: { grading.blending = $0; onChange() })
    }
    private var balanceBinding: Binding<Double> {
        Binding(get: { grading.balance }, set: { grading.balance = $0; onChange() })
    }

    private func labeledSlider(_ title: String, _ value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.caption)
                Spacer()
                EditableSliderValueText(
                    value: value.wrappedValue,
                    displayText: signedControlText(value.wrappedValue),
                    inputRange: range,
                    onCommit: { value.wrappedValue = $0 }
                )
            }
            ResettableSlider(value: value, in: range, resetValue: 0)
        }
    }
}
