import SwiftUI
import Chromabase

// MARK: - 좌측 Film 탭 — 필름 특성 룩 선택
//
// 순정 네이티브 Form. 슬라이드와 네거티브를 각각 하나의 카드로 나눠 보여주고, 선택은 하나다.
// 선택한 필름을 한 번 더 누르면 해제된다 — 목록에 "없음" 항목을 따로 두지 않는 이유다.
// 필름 룩은 소스가 아니라 룩이므로 현상 프로세스(C-41/E-6/디지털 등)와 무관하게 어떤 프레임에나
// 적용된다.
struct FilmEmulationSection: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var frame: ScanFrame

    /// 슬라이더 기본값이자 더블클릭 리셋 지점.
    private let defaultIntensity = DevelopParameters().filmEmulationIntensity

    var body: some View {
        filmCard(
            model.text(AppLocalizedPhrase.filmTypeSlide),
            systemImage: "photo",
            films: FilmEmulation.films(of: .slide)
        )
        filmCard(
            model.text(AppLocalizedPhrase.filmTypeColorNegative),
            systemImage: "film",
            films: FilmEmulation.films(of: .negative)
        )

        if frame.params.filmEmulation != .none {
            Section {
                // 우측 인스펙터와 같은 슬라이더 구성(캡션 제목 + 인라인 값 + 슬라이더).
                // labelsHidden 이 없으면 Form 이 레이블 열을 잡아 슬라이더가 오른쪽으로 밀린다.
                InspectorSlider(
                    model.text(AppLocalizedPhrase.intensity),
                    value: intensityBinding,
                    range: 0...1,
                    doubleClickResetValue: defaultIntensity,
                    showsPercent: true
                )
                .labelsHidden()
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func filmCard(
        _ title: String,
        systemImage: String,
        films: [FilmEmulation]
    ) -> some View {
        Section {
            ForEach(films) { film in
                FilmEmulationRow(
                    film: film,
                    isSelected: frame.params.filmEmulation == film,
                    action: { toggle(film) }
                )
            }
        } header: {
            sectionHeader(title, systemImage: systemImage)
        }
    }

    /// 같은 필름을 다시 누르면 해제한다.
    private func toggle(_ film: FilmEmulation) {
        let selected = frame.params.filmEmulation == film ? FilmEmulation.none : film
        let turningOn = frame.params.filmEmulation == .none
        frame.updateParams {
            $0.filmEmulation = selected
            // 필름을 새로 켤 때만 기본 강도에서 시작한다. 필름끼리 바꿀 때는 사용자가 맞춰 둔
            // 강도를 그대로 둔다.
            if turningOn { $0.filmEmulationIntensity = defaultIntensity }
        }
        model.requestDevelop(frame)
    }

    private var intensityBinding: Binding<Double> {
        Binding(
            get: { frame.params.filmEmulationIntensity },
            set: { value in
                frame.updateParams { $0.filmEmulationIntensity = value }
                model.requestDevelop(frame)
            }
        )
    }
}

// MARK: - 필름 한 줄

private struct FilmEmulationRow: View {
    @EnvironmentObject private var model: AppModel
    let film: FilmEmulation
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(film.displayName)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(AppTypography.minimumScaleFactor)
                Spacer(minLength: 8)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .opacity(isSelected ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(film.displayName)
        .accessibilitySelectionState(
            isSelected,
            selectedValue: model.accessibilityText(.selected),
            unselectedValue: model.accessibilityText(.notSelected),
            selectedHint: model.accessibilityText(.turnOff),
            unselectedHint: model.accessibilityText(.select)
        )
    }
}
