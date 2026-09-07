import Chromabase
import SwiftUI

struct DevelopDefaultsSection: View {
    @EnvironmentObject var model: AppModel
    var availableWidth: CGFloat? = nil

    // grouped Form의 좌우 여백을 제외한 폭으로 제한해 좁은 사이드바에서 CS가 밀려나지 않게 합니다.
    private var controlsWidth: CGFloat? { availableWidth.map { max(0, $0 - 56) } }

    var body: some View {
        Section {
            Picker(model.text(AppLocalizedPhrase.process), selection: developmentProcessBinding) {
                ForEach(DevelopmentProcess.allCases, id: \.self) { process in
                    Text(process.displayName).tag(process)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(model.text(AppLocalizedPhrase.target))
                SegmentedPicker(
                    options: DevelopTargetFamily.allCases,
                    label: { $0.displayName },
                    selection: targetBinding,
                    compressLabels: true,
                    accessibilityName: { $0 == .custom ? model.text(.customTargetTitle) : $0.displayName }
                )
            }
            .frame(width: controlsWidth)
            .accessibilityIdentifier("negaflow.develop.target-family")

            profileAndLookRow
                .frame(width: controlsWidth)
            if model.activeWorkspaceModule == .develop, let frame = model.actionableFrame {
                InputGammaControlSection(frame: frame)
                    .id("\(frame.id)-\(frame.sourceLocationRevision)")
            }
        } header: {
            sectionHeader(model.text(.developDefaults), systemImage: "camera.filters")
        }
    }

    private var activeDevelopTarget: DevelopTarget {
        model.actionableFrame?.params.developTarget ?? model.developTarget
    }

    private var activeFilmType: FilmType {
        model.actionableFrame?.filmType ?? model.filmType
    }

    private var targetFamily: DevelopTargetFamily {
        DevelopTargetFamily(target: activeDevelopTarget)
    }

    private var targetProfileBinding: Binding<DevelopTarget> {
        Binding(
            get: {
                switch activeDevelopTarget {
                case .print, .rescue:
                    return activeDevelopTarget
                default:
                    return activeDevelopTarget
                }
            },
            set: { selection in
                guard targetFamily == .main else { return }
                model.applyDevelopTarget(selection, to: model.actionableFrame)
            }
        )
    }

    private var profileAndLookRow: some View {
        // 양쪽에 fixedSize를 걸면 사이드바가 좁아질 때 줄어드는 대신 행을 넘겨서 오른쪽이
        // 잘린다. 룩은 번들 프리셋뿐이라 이름이 짧으니 고정폭으로 두고, 길이가 들쭉날쭉한
        // 필름 프로파일이 남는 폭을 흡수하며 말줄임되게 한다.
        HStack(spacing: 8) {
            filmProfileControl
                .frame(maxWidth: .infinity, alignment: .leading)

            Picker(model.text(AppLocalizedPhrase.look), selection: lookPresetBinding) {
                ForEach(model.presets) { preset in
                    Text(preset.name).tag(LookPreset?.some(preset))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize(horizontal: true, vertical: false)
            .disabled(model.actionableFrame == nil)
        }
    }

    @ViewBuilder
    private var filmProfileControl: some View {
        if targetFamily == .main {
            Picker(model.text(AppLocalizedPhrase.filmProfile), selection: targetProfileBinding) {
                Text(DevelopTarget.main.displayName(language: model.appLanguage)).tag(DevelopTarget.main)
                Text(DevelopTarget.print.displayName(language: model.appLanguage)).tag(DevelopTarget.print)
                Text(DevelopTarget.rescue.displayName(language: model.appLanguage)).tag(DevelopTarget.rescue)
            }
            .labelsHidden()
        } else if targetFamily == .hs || targetFamily == .sp {
            Picker(model.text(AppLocalizedPhrase.filmProfile), selection: scannerProfileBinding) {
                Text(activeDevelopTarget.displayName(language: model.appLanguage)).tag(String?.none)
                ForEach(filteredScannerProfiles) { profile in
                    Text(profile.compactFilmName).tag(profile.id as String?)
                }
            }
            .labelsHidden()
        } else if targetFamily == .custom {
            CustomTargetPicker(selection: customTargetBinding)
        } else {
            Text(activeDevelopTarget.displayName(language: model.appLanguage))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var neutralPreset: LookPreset? {
        model.presets.first(where: { $0.id == "neutral" })
    }

    private var lookPresetBinding: Binding<LookPreset?> {
        Binding(
            get: { model.actionableFrame?.preset ?? neutralPreset },
            set: { preset in
                guard let frame = model.actionableFrame, let preset else { return }
                frame.preset = preset
                Task { await model.developFrame(frame) }
            }
        )
    }

    private var filteredScannerProfiles: [ScannerProfile] {
        ScannerProfileMatcher.matchingProfiles(
            target: activeDevelopTarget,
            filmType: activeFilmType,
            profiles: model.scannerProfiles
        )
    }

    private var targetBinding: Binding<DevelopTargetFamily> {
        Binding(
            get: { targetFamily },
            set: { family in
                model.applyDevelopTarget(family.selection(from: activeDevelopTarget), to: model.actionableFrame)
            }
        )
    }

    private var customTargetBinding: Binding<DevelopTarget> {
        Binding(
            get: { activeDevelopTarget },
            set: { target in
                guard target.isCustom, target != activeDevelopTarget else { return }
                model.applyDevelopTarget(target, to: model.actionableFrame)
            }
        )
    }

    private var developmentProcessBinding: Binding<DevelopmentProcess> {
        Binding(
            get: { model.activeDevelopmentProcess },
            set: { model.applyDevelopmentProcess($0, to: model.actionableFrame) }
        )
    }

    private var scannerProfileBinding: Binding<String?> {
        Binding(
            get: { model.actionableFrame?.params.scannerProfileID ?? model.scannerProfileID },
            set: { profileID in
                model.scannerProfileID = profileID
                guard let frame = model.actionableFrame else { return }
                frame.updateParams { $0.scannerProfileID = profileID }
                Task { await model.developFrame(frame) }
            }
        )
    }

}
