import SwiftUI
import Chromabase
import ScannerKit

// MARK: - LibrarySourceSection (좌측 Library 첫 화면 — Lightroom식 진입점)
//
// 두 진입점으로 시작한다:
//   ① 이미지 가져오기 — 파일 선택(다중) 또는 드래그앤드롭으로 RAW/DNG/TIFF/PNG/JPG 가져오기.
//   ② 스캐너 불러오기 — 설치된 스캐너 플러그인(또는 시뮬레이터)으로 스캔.
// 두 경로 모두 동일한 현상 워크플로우로 수렴한다. 현상 기본값(Target/Film/Profile)은 여기서
// 공유한다.
struct LibrarySourceSection: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Section {
            Button {
                model.presentImportPanel()
            } label: {
                Label("이미지 가져오기", systemImage: "photo.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Text("파일 선택(다중) 또는 이미지를 창에 드래그앤드롭하세요.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                withAnimation(.snappy(duration: 0.18)) { model.showScannerControls.toggle() }
            } label: {
                HStack {
                    Label("스캐너 불러오기", systemImage: "scanner")
                    Spacer()
                    Image(systemName: scannerRevealed ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        } header: {
            sectionHeader("가져오기", systemImage: "tray.and.arrow.down")
        }

        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Target")
                SegmentedPicker(
                    options: scanTargets,
                    label: { $0.displayName },
                    selection: targetBinding
                )
            }

            Picker("Film Profile", selection: scannerProfileBinding) {
                if filteredScannerProfiles.isEmpty {
                    Text(scannerProfilePlaceholder).tag(String?.none)
                } else {
                    ForEach(filteredScannerProfiles) { profile in
                        Text(profile.filmKey.capitalized).tag(profile.id as String?)
                    }
                }
            }
            .disabled(filteredScannerProfiles.isEmpty)

            Picker("Look", selection: lookPresetBinding) {
                Text("없음").tag(LookPreset?.none)
                ForEach(model.presets) { preset in
                    Text(preset.name).tag(LookPreset?.some(preset))
                }
            }
            .disabled(model.selectedFrame == nil)

            Picker("Film", selection: filmTypeBinding) {
                ForEach(FilmType.allCases, id: \.self) { filmType in
                    Text(filmType.displayName).tag(filmType)
                }
            }
        } header: {
            sectionHeader("현상 기본값", systemImage: "camera.filters")
        }

        if scannerRevealed {
            ScannerControlsSection()
        }
    }

    var scannerRevealed: Bool { model.showScannerControls || model.hasScanner }

    // MARK: - 공유 현상 기본값 바인딩/헬퍼 (가져오기·스캔 공통)

    var scanTargets: [DevelopTarget] { DevelopTarget.allCases }

    var activeDevelopTarget: DevelopTarget {
        model.selectedFrame?.params.developTarget ?? model.developTarget
    }

    var activeFilmType: FilmType {
        model.selectedFrame?.filmType ?? model.filmType
    }

    var scannerProfilePlaceholder: String {
        switch activeDevelopTarget {
        case .main, .print:
            return activeDevelopTarget.displayName
        case .noritsu, .sp3000:
            return "수동 선택"
        }
    }

    var filteredScannerProfiles: [ScannerProfile] {
        ScannerProfileMatcher.matchingProfiles(
            target: activeDevelopTarget,
            filmType: activeFilmType,
            profiles: model.scannerProfiles
        )
    }

    var targetBinding: Binding<DevelopTarget> {
        Binding(get: { activeDevelopTarget }, set: { applyDevelopTarget($0) })
    }

    var filmTypeBinding: Binding<FilmType> {
        Binding(get: { activeFilmType }, set: { applyFilmType($0) })
    }

    var scannerProfileBinding: Binding<String?> {
        Binding(
            get: { model.selectedFrame?.params.scannerProfileID ?? model.scannerProfileID },
            set: { profileID in
                model.scannerProfileID = profileID
                guard let frame = model.selectedFrame else { return }
                frame.updateParams { $0.scannerProfileID = profileID }
                Task { await model.developFrame(frame) }
            }
        )
    }

    var lookPresetBinding: Binding<LookPreset?> {
        Binding(
            get: { model.selectedFrame?.preset },
            set: { preset in
                guard let frame = model.selectedFrame else { return }
                frame.preset = preset
                Task { await model.developFrame(frame) }
            }
        )
    }

    func applyDevelopTarget(_ target: DevelopTarget) {
        model.developTarget = target
        let profileID = compatibleManualScannerProfileID(target: target, filmType: activeFilmType)
        model.scannerProfileID = profileID
        guard let frame = model.selectedFrame else { return }
        frame.updateParams {
            $0.developTarget = target
            $0.scannerProfileID = profileID
        }
        Task { await model.developFrame(frame) }
    }

    func applyFilmType(_ filmType: FilmType) {
        model.filmType = filmType
        let profileID = compatibleManualScannerProfileID(target: activeDevelopTarget, filmType: filmType)
        model.scannerProfileID = profileID
        guard let frame = model.selectedFrame else { return }
        frame.filmType = filmType
        frame.updateParams {
            $0.filmType = filmType
            $0.scannerProfileID = profileID
        }
        Task { await model.developFrame(frame) }
    }

    func compatibleManualScannerProfileID(target: DevelopTarget, filmType: FilmType) -> String? {
        let currentID = model.selectedFrame?.params.scannerProfileID ?? model.scannerProfileID
        guard let currentID else { return nil }
        let matches = ScannerProfileMatcher.matchingProfiles(
            target: target, filmType: filmType, profiles: model.scannerProfiles
        )
        return matches.contains(where: { $0.id == currentID }) ? currentID : nil
    }
}
