import SwiftUI
import Chromabase

/// 색상 혼합(HSL) — 색조/채도/광도/모두 캡슐 + 8색(빨강~자홍) 슬라이더.
struct ColorMixerSection: View {
    @EnvironmentObject private var model: AppModel
    @Binding var mixer: ColorMixer
    let onChange: () -> Void
    @State private var property: Property = .hue

    enum Property: String, CaseIterable, Identifiable {
        case hue, saturation, luminance, all
        var id: Self { self }
        func label(language: AppLanguage) -> String {
            switch self {
            case .hue: return AppLocalization.text(AppLocalizedPhrase.hue, language: language)
            case .saturation: return AppLocalization.text(AppLocalizedPhrase.saturation, language: language)
            case .luminance: return AppLocalization.text(AppLocalizedPhrase.luminance, language: language)
            case .all: return AppLocalization.text(AppLocalizedPhrase.all, language: language)
            }
        }
    }

    private static let bands: [(name: AppLocalizedPhrase, color: Color)] = [
        (.red, Color(red: 0.90, green: 0.20, blue: 0.20)),
        (.orange, Color(red: 0.93, green: 0.55, blue: 0.18)),
        (.yellow, Color(red: 0.88, green: 0.82, blue: 0.20)),
        (.green, Color(red: 0.25, green: 0.72, blue: 0.34)),
        (.aqua, Color(red: 0.20, green: 0.76, blue: 0.78)),
        (.blue, Color(red: 0.24, green: 0.42, blue: 0.90)),
        (.purple, Color(red: 0.55, green: 0.30, blue: 0.86)),
        (.magenta, Color(red: 0.88, green: 0.28, blue: 0.66)),
    ]

    var body: some View {
        VStack(spacing: 10) {
            CapsuleSegmented(
                options: Property.allCases,
                label: { $0.label(language: model.appLanguage) },
                selection: $property
            )

            if property == .all {
                ForEach(0..<8, id: \.self) { i in
                    VStack(spacing: 3) {
                        HStack(spacing: 6) {
                            swatch(i)
                            Text(model.text(Self.bands[i].name)).font(.caption.weight(.medium))
                            Spacer()
                        }
                        miniSlider("H", binding(\.hue, i))
                        miniSlider("S", binding(\.saturation, i))
                        miniSlider("L", binding(\.luminance, i))
                    }
                    .padding(.bottom, 2)
                }
            } else {
                ForEach(0..<8, id: \.self) { i in
                    swatchSlider(i, binding(propertyKeyPath, i))
                }
            }
        }
    }

    private var propertyKeyPath: WritableKeyPath<ColorMixer, [Double]> {
        switch property {
        case .hue: return \.hue
        case .saturation: return \.saturation
        case .luminance, .all: return \.luminance
        }
    }

    private func binding(_ keyPath: WritableKeyPath<ColorMixer, [Double]>, _ index: Int) -> Binding<Double> {
        Binding(
            get: { mixer[keyPath: keyPath][index] },
            set: { mixer[keyPath: keyPath][index] = $0; onChange() }
        )
    }

    private func swatch(_ i: Int) -> some View {
        Circle().fill(Self.bands[i].color).frame(width: 12, height: 12)
            .overlay(Circle().stroke(.white.opacity(0.3), lineWidth: 0.5))
    }

    private func swatchSlider(_ i: Int, _ value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                swatch(i)
                Text(model.text(Self.bands[i].name)).font(.caption)
                Spacer()
                EditableSliderValueText(
                    value: value.wrappedValue,
                    displayText: signedControlText(value.wrappedValue),
                    inputRange: -1...1,
                    width: 44,
                    onCommit: { value.wrappedValue = $0 }
                )
            }
            ResettableSlider(value: value, in: -1...1, resetValue: 0)
        }
    }

    private func miniSlider(_ tag: String, _ value: Binding<Double>) -> some View {
        HStack(spacing: 6) {
            Text(tag).font(.caption2.monospacedDigit()).foregroundStyle(.secondary).frame(width: 12)
            ResettableSlider(value: value, in: -1...1, resetValue: 0)
            EditableSliderValueText(
                value: value.wrappedValue,
                displayText: signedControlText(value.wrappedValue),
                inputRange: -1...1,
                width: 38,
                onCommit: { value.wrappedValue = $0 }
            )
        }
    }
}

/// 내부 가로 캡슐 세그먼트 선택기(색조/채도/광도/모두 등).
struct CapsuleSegmented<Option: Hashable>: View {
    let options: [Option]
    let label: (Option) -> String
    @Binding var selection: Option

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    Text(label(option))
                        .font(.caption.weight(selection == option ? .semibold : .regular))
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                        .foregroundStyle(selection == option ? Color.primary : Color.secondary)
                        .background(selection == option ? Color.primary.opacity(0.12) : Color.clear,
                                    in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.05), in: Capsule())
    }
}
