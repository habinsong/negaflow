import AppKit
import Chromabase
import SwiftUI
import UniformTypeIdentifiers

struct ColorManagementSettingsSection: View {
    private enum ProfileDestination: Equatable {
        case softProof
        case printerOutput
    }

    @EnvironmentObject private var model: AppModel
    @State private var failedProfileSelection: ProfileDestination?

    var body: some View {
        AppSettingsSection(
            title: model.text(.colorManagementSection)
        ) {
            AppSettingsRow(model.text(.exportColorLabel)) {
                Picker(String(), selection: $model.exportColorSpace) {
                    ForEach(ExportColorSpace.allCases, id: \.self) { space in
                        Text(space.uiLabel).tag(space)
                    }
                }
                .labelsHidden()
            }

            AppSettingsToggleRow(
                label: model.text(.exportSoftProofLabel),
                isOn: $model.softProofEnabled
            )

            if model.softProofEnabled {
                AppSettingsRow(model.text(AppLocalizedPhrase.profile)) {
                    HStack(spacing: 6) {
                        AppSettingsPathText(
                            text: model.softProofICCProfileName
                                ?? model.exportColorSpace.uiLabel
                        )

                        Button(model.text(.exportChangeFolder)) {
                            chooseProfile(for: .softProof)
                        }
                        .buttonStyle(.bordered)

                        if model.softProofICCProfileData != nil {
                            Button(model.text(AppLocalizedPhrase.reset)) {
                                model.clearSoftProofICCProfile()
                                failedProfileSelection = nil
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                if failedProfileSelection == .softProof {
                    AppSettingsHelpText(
                        model.text(AppLocalizedPhrase.softProofInvalidICC),
                        color: .red
                    )
                }

                AppSettingsRow(model.text(.exportProofLabel)) {
                    Picker(String(), selection: $model.softProofSimulation) {
                        ForEach(SoftProofSimulation.allCases, id: \.self) { simulation in
                            Text(softProofSimulationLabel(simulation)).tag(simulation)
                        }
                    }
                    .labelsHidden()
                }

                AppSettingsToggleRow(
                    label: model.text(AppLocalizedPhrase.colorGamutWarning),
                    isOn: $model.destinationGamutWarningEnabled,
                    isDisabled: !model.destinationGamutWarningAvailable
                )

                if !model.destinationGamutWarningAvailable {
                    AppSettingsHelpText(model.text(.colorGamutUnavailableReason))
                }
            }

            AppSettingsRow(model.text(.printOutputProfile)) {
                HStack(spacing: 6) {
                    AppSettingsPathText(
                        text: model.printerOutputICCProfileName ?? model.text(.colorUnassigned)
                    )

                    Button(model.text(.exportChangeFolder)) {
                        chooseProfile(for: .printerOutput)
                    }
                    .buttonStyle(.bordered)

                    if model.printerOutputICCProfileData != nil {
                        Button(model.text(AppLocalizedPhrase.reset)) {
                            model.clearPrinterOutputICCProfile()
                            failedProfileSelection = nil
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            if failedProfileSelection == .printerOutput {
                AppSettingsHelpText(model.text(AppLocalizedPhrase.softProofInvalidICC), color: .red)
            }

            AppSettingsValueRow(
                label: model.text(AppLocalizedPhrase.colorScannerInput),
                value: scannerEmulationSummary,
                supported: model.actionableFrame?.params.scannerProfileID != nil,
                reason: model.text(.colorScannerInputReason)
            )
            AppSettingsValueRow(
                label: model.text(AppLocalizedPhrase.colorWorking),
                value: "Linear sRGB (Chromabase)"
            )
            AppSettingsValueRow(
                label: model.text(AppLocalizedPhrase.colorMonitor),
                value: monitorProfileSummary
            )
            AppSettingsValueRow(
                label: model.text(AppLocalizedPhrase.colorExport),
                value: model.exportColorSpace.uiLabel
            )
            AppSettingsValueRow(
                label: model.text(AppLocalizedPhrase.colorSoftProof),
                value: softProofSummary,
                supported: model.softProofEnabled,
                reason: model.text(.colorSoftProofOffReason)
            )
        }
    }

    private var scannerEmulationSummary: String {
        guard let profileID = model.actionableFrame?.params.scannerProfileID else {
            return model.text(.colorUnassigned)
        }
        if let profile = model.scannerProfiles.first(where: { $0.id == profileID }) {
            return profile.displayName
        }
        return profileID
    }

    private var monitorProfileSummary: String {
        NSScreen.main?.colorSpace?.localizedName
            ?? model.text(.colorSystemDisplayProfile)
    }

    private var softProofSummary: String {
        guard model.softProofEnabled else { return model.text(.colorOff) }
        return model.text(
            AppLocalizedPhrase.softProofSummaryFormat,
            model.softProofICCProfileName ?? model.exportColorSpace.uiLabel,
            softProofSimulationLabel(model.softProofSimulation)
        )
    }

    private func softProofSimulationLabel(_ simulation: SoftProofSimulation) -> String {
        switch simulation {
        case .profileOnly:
            model.text(AppLocalizedPhrase.softProofProfileOnly)
        case .paperAndBlackInk:
            model.text(AppLocalizedPhrase.softProofPaperAndBlack)
        }
    }

    private func chooseProfile(for destination: ProfileDestination) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = ["icc", "icm"].compactMap {
            UTType(filenameExtension: $0)
        }
        panel.prompt = model.text(AppLocalizedPhrase.choose)
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                guard let data = try? Data(contentsOf: url),
                      let colorSpace = SoftProof.rgbOutputColorSpace(fromICCData: data) else {
                    failedProfileSelection = destination
                    return
                }
                let localizedName = NSColorSpace(cgColorSpace: colorSpace)?.localizedName
                let name = localizedName.flatMap { $0.isEmpty ? nil : $0 }
                    ?? url.deletingPathExtension().lastPathComponent
                let accepted = switch destination {
                case .softProof: model.setSoftProofICCProfile(data: data, name: name)
                case .printerOutput: model.setPrinterOutputICCProfile(data: data, name: name)
                }
                failedProfileSelection = accepted ? nil : destination
            }
        }
    }
}
