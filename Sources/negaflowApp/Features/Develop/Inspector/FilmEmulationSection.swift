import SwiftUI
import Chromabase

// MARK: - 좌측 Film 탭 — 필름 특성 룩 선택
//
// 순정 네이티브 Form. 슬라이드/네거티브를 나눠 보여주지만 선택은 하나다. 필름 룩은 소스가 아니라
// 룩이므로 현상 프로세스(C-41/E-6/디지털 등)와 무관하게 어떤 프레임에나 적용된다.
struct FilmEmulationSection: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var frame: ScanFrame

    /// 슬라이더 기본값이자 더블클릭 리셋 지점.
    private let defaultIntensity = DevelopParameters().filmEmulationIntensity

    var body: some View {
        Section {
            Picker(selection: filmBinding) {
                Text(FilmEmulation.none.displayName).tag(FilmEmulation.none)

                Section(model.text(AppLocalizedPhrase.filmTypeSlide)) {
                    filmRows(FilmEmulation.films(of: .slide))
                }
                Section(model.text(AppLocalizedPhrase.filmTypeColorNegative)) {
                    filmRows(FilmEmulation.films(of: .negative))
                }
            } label: { EmptyView() }
            .labelsHidden()
            .pickerStyle(.inline)
        } header: {
            sectionHeader(model.text(AppLocalizedPhrase.baseModeFilm), systemImage: "camera.filters")
        }

        if frame.params.filmEmulation != .none {
            Section {
                // 우측 인스펙터와 같은 슬라이더 구성을 그대로 쓴다(캡션 제목 + 인라인 값 + 슬라이더).
                InspectorSlider(
                    model.text(AppLocalizedPhrase.intensity),
                    value: intensityBinding,
                    range: 0...1,
                    doubleClickResetValue: defaultIntensity,
                    showsPercent: true
                )
            }
        }
    }

    private func filmRows(_ films: [FilmEmulation]) -> some View {
        ForEach(films) { film in
            Text(film.displayName).tag(film)
        }
    }

    private var filmBinding: Binding<FilmEmulation> {
        Binding(
            get: { frame.params.filmEmulation },
            set: { film in
                guard film != frame.params.filmEmulation else { return }
                let turningOn = frame.params.filmEmulation == .none
                frame.updateParams {
                    $0.filmEmulation = film
                    // 필름을 새로 켤 때만 기본 강도에서 시작한다. 필름끼리 바꿀 때는 사용자가
                    // 맞춰 둔 강도를 그대로 둔다.
                    if turningOn { $0.filmEmulationIntensity = defaultIntensity }
                }
                model.requestDevelop(frame)
            }
        )
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
