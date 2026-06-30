import SwiftUI
import Chromabase

/// 색보정(Color Grading) — 어두운/중간/밝은 영역 캡슐 + 색상환(색조·채도) + 광도 슬라이더,
/// 전역 혼합(blending)/균형(balance) 슬라이더.
struct ColorGradingSection: View {
    @Binding var grading: ColorGrading
    let onChange: () -> Void
    @State private var region: Region = .midtones

    enum Region: String, CaseIterable, Identifiable {
        case shadows, midtones, highlights
        var id: Self { self }
        var label: String {
            switch self {
            case .shadows: return "어두운 영역"
            case .midtones: return "중간 톤"
            case .highlights: return "밝은 영역"
            }
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            CapsuleSegmented(options: Region.allCases, label: { $0.label }, selection: $region)

            ColorWheelView(hue: hueBinding, saturation: satBinding, onChange: onChange)
                .frame(maxWidth: .infinity)

            HStack {
                Text("Hue").font(.caption).frame(width: 64, alignment: .leading)
                Text("\(Int(regionValue.hue.rounded()))°")
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                Text("Sat").font(.caption)
                Text(String(format: "%.0f%%", regionValue.saturation * 100))
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }

            labeledSlider("Luminance", lumBinding, range: -1...1)

            Divider().opacity(0.4)

            labeledSlider("Blending", blendingBinding, range: 0...1)
            labeledSlider("Balance", balanceBinding, range: -1...1)
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
                Text(signedControlText(value.wrappedValue))
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }
}
