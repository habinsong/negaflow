import AppKit
import Chromabase
import SwiftUI
import UniformTypeIdentifiers

struct PrintWorkspaceInspector: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var settingsStore: PrintWorkspaceSettingsStore

    var body: some View {
        VStack(spacing: 0) {
            inspectorHeader
            Divider()
            Form {
                layoutSection
                simulationSection
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .adaptivePanelSurface(.regular)
        .clipped()
    }

    private var inspectorHeader: some View {
        HStack(spacing: 8) {
            Label(model.text(.menuPrint), systemImage: "printer")
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 8)
            Text(model.actionableFrame?.compactDisplayName(language: model.appLanguage) ?? model.text(.noFrame))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(AppTypography.minimumScaleFactor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .adaptivePanelSurface(.bar)
    }

    private var layoutSection: some View {
        Section {
            Picker(model.text(.printLayoutMode), selection: $settingsStore.layoutMode) {
                ForEach(PrintWorkspaceLayoutMode.allCases, id: \.self) { mode in
                    Text(layoutModeTitle(mode)).tag(mode)
                }
            }

            Picker(model.text(.printPaperSize), selection: $settingsStore.paperSize) {
                ForEach(PrintPaperSize.allCases, id: \.self) { size in
                    Text(size.uiLabel).tag(size)
                }
            }

            Picker(model.text(.printOrientation), selection: $settingsStore.orientation) {
                Text(model.text(.printOrientationAutomatic)).tag(PrintPaperOrientation.automatic)
                Text(model.text(.printOrientationPortrait)).tag(PrintPaperOrientation.portrait)
                Text(model.text(.printOrientationLandscape)).tag(PrintPaperOrientation.landscape)
            }

            HStack(spacing: 10) {
                Text(model.text(.printMargin))
                Slider(value: $settingsStore.marginMM, in: 0...50, step: 1)
                Text("\(Int(settingsStore.marginMM.rounded())) mm")
                    .font(.caption.monospacedDigit())
                    .frame(width: 46, alignment: .trailing)
            }

            if settingsStore.layoutMode != .singleImage {
                PrintPackageInspectorControls(settingsStore: settingsStore)
            }

            PrintLayoutTemplateControls(settingsStore: settingsStore)
        } header: {
            sectionHeader(model.text(.printLayoutSection), systemImage: "rectangle.inset.filled")
        }
    }

    private func layoutModeTitle(_ mode: PrintWorkspaceLayoutMode) -> String {
        switch mode {
        case .singleImage: model.text(.printSingleImage)
        case .contactSheet: model.text(.printContactSheet)
        case .picturePackage: model.text(.printPicturePackage)
        case .customPackage: model.text(.printCustomPackage)
        }
    }

    private var simulationSection: some View {
        Section {
            Toggle(model.text(.printFilmSimulation), isOn: filmSimulationBinding)
                .disabled(model.actionableFrame == nil)

            Toggle(model.text(.exportSoftProofLabel), isOn: $model.softProofEnabled)

            Toggle(model.text(.printPaperSimulation), isOn: paperSimulationBinding)
                .disabled(!model.softProofEnabled)

            LabeledContent(model.text(.printOutputProfile)) {
                HStack(spacing: 6) {
                    Text(model.printerOutputICCProfileName ?? "—")
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button(model.text(.exportChangeFolder)) {
                        choosePrinterOutputProfile()
                    }
                    .controlSize(.small)
                    if model.printerOutputICCProfileData != nil {
                        Button(model.text(AppLocalizedPhrase.reset)) {
                            model.clearPrinterOutputICCProfile()
                        }
                        .controlSize(.small)
                    }
                }
            }

            if model.softProofEnabled {
                Toggle(
                    model.text(AppLocalizedPhrase.colorGamutWarning),
                    isOn: $model.destinationGamutWarningEnabled
                )
                .disabled(!model.destinationGamutWarningAvailable)

            }
        } header: {
            sectionHeader(model.text(.menuPrint), systemImage: "camera.filters")
        }
    }

    private var filmSimulationBinding: Binding<Bool> {
        Binding(
            get: { model.actionableFrame?.params.developTarget == .print },
            set: { enabled in
                guard let frame = model.actionableFrame else { return }
                let target: DevelopTarget = enabled ? .print : .main
                model.developTarget = target
                model.scannerProfileID = nil
                frame.updateParams {
                    $0.developTarget = target
                    $0.scannerProfileID = nil
                }
                Task { await model.developFrame(frame) }
            }
        )
    }

    private var paperSimulationBinding: Binding<Bool> {
        Binding(
            get: { model.softProofEnabled && model.softProofSimulation == .paperAndBlackInk },
            set: { enabled in
                model.softProofSimulation = enabled ? .paperAndBlackInk : .profileOnly
            }
        )
    }

    private func choosePrinterOutputProfile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = ["icc", "icm"].compactMap { UTType(filenameExtension: $0) }
        panel.prompt = model.text(AppLocalizedPhrase.choose)
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                guard let data = try? Data(contentsOf: url),
                      let profile = ICCOutputProfileSnapshot(
                          profileName: url.deletingPathExtension().lastPathComponent,
                          iccProfileData: data
                      ), let colorSpace = profile.validatedColorSpace() else { return }
                let localizedName = NSColorSpace(cgColorSpace: colorSpace)?.localizedName
                let name = localizedName.flatMap { $0.isEmpty ? nil : $0 } ?? profile.profileName
                _ = model.setPrinterOutputICCProfile(
                    data: data,
                    name: name
                )
            }
        }
    }
}
