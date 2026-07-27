import SwiftUI
import Chromabase

enum LibrarySourceContent {
    case combined
    case importing
    case files
}

struct LibrarySourceSection: View {
    @EnvironmentObject var model: AppModel
    var content = LibrarySourceContent.combined
    var showsDevelopDefaults = true
    var orderedResultFrameIDs: [UUID]? = nil
    var selectedFolderID: Binding<String?> = .constant(nil)
    var visibleFolderPaths: Set<String>? = nil

    @ViewBuilder
    var body: some View {
        switch content {
        case .combined:
            Form {
                importSections
                Section {
                    LibraryFolderTreeView(
                        orderedResultFrameIDs: orderedResultFrameIDs,
                        selectedFolderID: selectedFolderID,
                        visibleFolderPaths: visibleFolderPaths
                    )
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .contextMenu { newFolderButton }
        case .importing:
            importContent
        case .files:
            filesContent
        }
    }

    private var importContent: some View {
        Form {
            importSections
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private var importSections: some View {
        Section {
            importActionBar
        } header: {
            sectionHeader(model.text(.importSection), systemImage: "square.and.arrow.down")
        }

        if model.showScannerControls {
            ScannerControlsSection()
        }

        if showsDevelopDefaults {
            DevelopDefaultsSection()
        }
    }

    private var filesContent: some View {
        ScrollView {
            LibraryFolderTreeView(
                orderedResultFrameIDs: orderedResultFrameIDs,
                selectedFolderID: selectedFolderID,
                visibleFolderPaths: visibleFolderPaths
            )
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contextMenu {
            newFolderButton
        }
    }

    private var newFolderButton: some View {
        Button(model.text(AppLocalizedPhrase.newFolder)) {
            model.presentCreateLibraryFolder(
                in: model.defaultLibraryFolderCreationParent(
                    selectedFolderID: selectedFolderID.wrappedValue
                )
            )
        }
    }

    private var importActionBar: some View {
        HStack(spacing: 0) {
            ImportGlassAction(
                title: model.text(AppLocalizedPhrase.importImageShort),
                systemImage: "photo.badge.plus",
                action: model.presentImportPanel
            )
            importDivider
            ImportGlassAction(
                title: model.text(AppLocalizedPhrase.importFolderShort),
                systemImage: "folder.badge.plus",
                action: model.presentImportFolderPanel
            )
            importDivider
            ImportGlassAction(
                title: model.text(AppLocalizedPhrase.scannerLabel),
                systemImage: "scanner",
                action: {
                    withAnimation(.snappy(duration: 0.18)) {
                        model.presentScannerSetup()
                    }
                }
            )
        }
        .padding(2)
        .liquidSurface(cornerRadius: 16, interactive: true)
    }

    private var importDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: 1, height: 16)
            .padding(.horizontal, 2)
    }
}

private struct ImportGlassAction: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(AppTypography.minimumScaleFactor)
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .padding(.horizontal, 6)
                .background(
                    Color.primary.opacity(isHovered ? 0.12 : 0),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct DevelopDefaultsSection: View {
    @EnvironmentObject var model: AppModel

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
                    options: visibleTargets,
                    label: { $0.displayName(language: model.appLanguage) },
                    selection: targetBinding
                )
            }

            profileAndLookRow
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

    private var targetFamily: DevelopTarget {
        switch activeDevelopTarget {
        case .print, .rescue:
            return .main
        default:
            return activeDevelopTarget
        }
    }

    private var visibleTargets: [DevelopTarget] {
        [.main, .noritsu, .sp3000, .f135, .hr]
    }

    private var targetProfileBinding: Binding<DevelopTarget> {
        Binding(
            get: {
                switch activeDevelopTarget {
                case .print, .rescue:
                    return activeDevelopTarget
                default:
                    return targetFamily
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
        } else if targetFamily == .noritsu || targetFamily == .sp3000 {
            Picker(model.text(AppLocalizedPhrase.filmProfile), selection: scannerProfileBinding) {
                Text(targetFamily.displayName(language: model.appLanguage)).tag(String?.none)
                ForEach(filteredScannerProfiles) { profile in
                    Text(profile.compactFilmName).tag(profile.id as String?)
                }
            }
            .labelsHidden()
        } else {
            Text(targetFamily.displayName(language: model.appLanguage))
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
            target: targetFamily,
            filmType: activeFilmType,
            profiles: model.scannerProfiles
        )
    }

    private var targetBinding: Binding<DevelopTarget> {
        Binding(
            get: { targetFamily },
            set: { model.applyDevelopTarget($0, to: model.actionableFrame) }
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
