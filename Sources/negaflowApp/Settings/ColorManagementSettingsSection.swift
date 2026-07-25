import SwiftUI
import AppKit
import Chromabase
import UniformTypeIdentifiers

struct ColorManagementSettingsSection: View {
    @EnvironmentObject private var model: AppModel
    @State private var profileSelectionFailed = false

    var body: some View {
        Section {
            Picker(model.text(.exportColorLabel), selection: $model.exportColorSpace) {
                ForEach(ExportColorSpace.allCases, id: \.self) { space in
                    Text(space.uiLabel).tag(space)
                }
            }

            Toggle(model.text(.exportSoftProofLabel), isOn: $model.softProofEnabled)

            if model.softProofEnabled {
                LabeledContent(model.text(AppLocalizedPhrase.profile)) {
                    HStack(spacing: 6) {
                        Text(model.softProofICCProfileName ?? model.exportColorSpace.uiLabel)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button(model.text(.exportChangeFolder)) {
                            chooseSoftProofProfile()
                        }
                        .controlSize(.small)
                        if model.softProofICCProfileData != nil {
                            Button(model.text(AppLocalizedPhrase.reset)) {
                                model.clearSoftProofICCProfile()
                                profileSelectionFailed = false
                            }
                            .controlSize(.small)
                        }
                    }
                }
                if profileSelectionFailed {
                    Text(model.text(AppLocalizedPhrase.softProofInvalidICC))
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
                Picker(model.text(.exportProofLabel), selection: $model.softProofSimulation) {
                    ForEach(SoftProofSimulation.allCases, id: \.self) { simulation in
                        Text(softProofSimulationLabel(simulation)).tag(simulation)
                    }
                }
                Toggle(
                    model.text(AppLocalizedPhrase.colorGamutWarning),
                    isOn: $model.destinationGamutWarningEnabled
                )
                .disabled(!model.destinationGamutWarningAvailable)
                if !model.destinationGamutWarningAvailable {
                    Text(model.text(.colorGamutUnavailableReason))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            colorRow(
                model.text(AppLocalizedPhrase.colorScannerInput),
                value: scannerEmulationSummary,
                supported: model.actionableFrame?.params.scannerProfileID != nil,
                reason: model.text(.colorScannerInputReason)
            )
            colorRow(model.text(AppLocalizedPhrase.colorWorking), value: "Linear sRGB (Chromabase)")
            colorRow(model.text(AppLocalizedPhrase.colorMonitor), value: monitorProfileSummary)
            colorRow(model.text(AppLocalizedPhrase.colorExport), value: model.exportColorSpace.uiLabel)
            colorRow(
                model.text(AppLocalizedPhrase.colorSoftProof),
                value: softProofSummary,
                supported: model.softProofEnabled,
                reason: model.text(.colorSoftProofOffReason)
            )
            PixelSamplerSettingsRow(
                store: model.pixelSamplerStore,
                language: model.appLanguage,
                onSetEnabled: { enabled in
                    model.setPixelSamplerEnabled(enabled)
                }
            )
            Toggle(
                model.text(AppLocalizedPhrase.colorClippingOverlay),
                isOn: $model.clippingOverlayEnabled
            )
        } header: {
            sectionHeader(model.text(.colorManagementSection), systemImage: "paintpalette")
        }
    }

    private var scannerEmulationSummary: String {
        guard let profileID = model.actionableFrame?.params.scannerProfileID else { return model.text(.colorUnassigned) }
        if let profile = model.scannerProfiles.first(where: { $0.id == profileID }) {
            return profile.displayName
        }
        return profileID
    }

    private var monitorProfileSummary: String {
        NSScreen.main?.colorSpace?.localizedName ?? model.text(.colorSystemDisplayProfile)
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
        case .profileOnly: model.text(AppLocalizedPhrase.softProofProfileOnly)
        case .paperAndBlackInk: model.text(AppLocalizedPhrase.softProofPaperAndBlack)
        }
    }

    private func chooseSoftProofProfile() {
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
                      let colorSpace = SoftProof.rgbOutputColorSpace(fromICCData: data) else {
                    profileSelectionFailed = true
                    return
                }
                let localizedName = NSColorSpace(cgColorSpace: colorSpace)?.localizedName
                let name = localizedName.flatMap { $0.isEmpty ? nil : $0 }
                    ?? url.deletingPathExtension().lastPathComponent
                profileSelectionFailed = !model.setSoftProofICCProfile(data: data, name: name)
            }
        }
    }

    @ViewBuilder
    private func colorRow(_ title: String, value: String, supported: Bool = true, reason: String? = nil) -> some View {
        LabeledContent(title) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .foregroundStyle(supported ? .primary : .secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                if !supported, let reason {
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }
}
