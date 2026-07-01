import SwiftUI
import Chromabase

// MARK: - 좌측 Film 탭 — 슬라이드 필름 특성 룩 선택
//
// 순정 네이티브 Form. 필름 선택 + Intensity 만.
struct FilmEmulationSection: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var frame: ScanFrame

    var body: some View {
        Section {
            Picker(selection: filmBinding) {
                ForEach(FilmEmulation.allCases) { film in
                    Text(film.displayName).tag(film)
                }
            } label: { EmptyView() }
            .labelsHidden()
            .pickerStyle(.inline)
        } header: {
            sectionHeader("Film", systemImage: "camera.filters")
        }

        if frame.params.filmEmulation != .none {
            Section {
                HStack {
                    Text("Intensity")
                    Spacer(minLength: 8)
                    Text("\(Int((frame.params.filmEmulationIntensity * 100).rounded()))%")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: intensityBinding, in: 0...1)
            }
        }
    }

    private var filmBinding: Binding<FilmEmulation> {
        Binding(
            get: { frame.params.filmEmulation },
            set: { film in
                guard film != frame.params.filmEmulation else { return }
                frame.updateParams { $0.filmEmulation = film }
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
