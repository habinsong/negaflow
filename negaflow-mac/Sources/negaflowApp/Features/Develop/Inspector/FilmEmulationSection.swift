import SwiftUI
import Chromabase

// MARK: - 좌측 Film 탭 — 필름 특성 룩 선택
//
// 순정 네이티브 Form. 필름 종류별로 카드를 나눠 보여주고, 선택은 하나다.
// 선택한 필름을 한 번 더 누르면 해제된다 — 목록에 "없음" 항목을 따로 두지 않는 이유다.
//
// 필름 룩은 **디지털 소스 전용**이다. 실제 필름을 스캔한 프레임(C-41 / ECN-2 / E-6 / D-76 /
// B&W Reversal)에는 이미 그 유제를 통과한 신호가 들어 있어 유제 응답을 두 번 먹이게 되므로,
// 그 프로세스에서는 목록 대신 그 사실만 알린다.
//
// 선택 자체는 프로세스가 바뀌어도 지우지 않는다. 사용자가 프로세스를 되돌리면 고르던 필름이
// 살아 돌아오는 편이 덜 놀랍고, 엔진도 프로세스와 종류가 어긋난 조합에는 룩을 걸지 않는다.
struct FilmEmulationSection: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var frame: ScanFrame

    /// 슬라이더 기본값이자 더블클릭 리셋 지점.
    private let defaultIntensity = DevelopParameters().filmEmulationIntensity

    private var isMonochrome: Bool {
        frame.filmType == .bwNegative || frame.filmType == .bwPositive
    }

    private var isDigitalSource: Bool {
        frame.params.isDigitalSource == true
    }

    var body: some View {
        if !isDigitalSource {
            Section {
                Text(model.text(AppLocalizedPhrase.filmLookDigitalOnly))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if isMonochrome {
            filmCard(
                model.text(AppLocalizedPhrase.filmGroupBWSlide),
                systemImage: "sun.max",
                films: FilmEmulation.films(of: .bwReversal)
            )
            filmCard(
                model.text(AppLocalizedPhrase.filmTypeBWNegative),
                systemImage: "circle.lefthalf.filled",
                films: FilmEmulation.films(of: .bwNegative)
            )
        } else {
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
            filmCard(
                model.text(AppLocalizedPhrase.filmGroupCinema),
                systemImage: "movieclapper",
                films: FilmEmulation.films(of: .motionPicture)
            )
        }

        if isDigitalSource, frame.params.filmEmulation != .none {
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
