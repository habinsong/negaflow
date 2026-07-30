import Chromabase
import SwiftUI

struct AppSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage(AppSettingsTab.defaultsKey)
    private var selectedTab: AppSettingsTab = .general

    var body: some View {
        TabView(selection: $selectedTab) {
            generalPane
                .tabItem {
                    Label(
                        model.text(.settingsGeneralTab),
                        systemImage: AppSettingsTab.general.systemImage
                    )
                }
                .tag(AppSettingsTab.general)

            interfacePane
                .tabItem {
                    Label(
                        model.text(.settingsInterfaceTab),
                        systemImage: AppSettingsTab.interface.systemImage
                    )
                }
                .tag(AppSettingsTab.interface)

            workflowPane
                .tabItem {
                    Label(
                        model.text(.settingsWorkflowTab),
                        systemImage: AppSettingsTab.workflow.systemImage
                    )
                }
                .tag(AppSettingsTab.workflow)

            scanPane
                .tabItem {
                    Label(
                        model.text(AppLocalizedPhrase.settingsScanTab),
                        systemImage: AppSettingsTab.scan.systemImage
                    )
                }
                .tag(AppSettingsTab.scan)

            diskPane
                .tabItem {
                    Label(
                        model.text(AppLocalizedPhrase.settingsDiskTab),
                        systemImage: AppSettingsTab.disk.systemImage
                    )
                }
                .tag(AppSettingsTab.disk)

            exportPane
                .tabItem {
                    Label(
                        model.text(.settingsExportTab),
                        systemImage: AppSettingsTab.export.systemImage
                    )
                }
                .tag(AppSettingsTab.export)

            shortcutsPane
                .tabItem {
                    Label(
                        model.text(.settingsShortcutsTab),
                        systemImage: AppSettingsTab.shortcuts.systemImage
                    )
                }
                .tag(AppSettingsTab.shortcuts)

            legalPane
                .tabItem {
                    Label(
                        model.text(.settingsLegalTab),
                        systemImage: AppSettingsTab.legal.systemImage
                    )
                }
                .tag(AppSettingsTab.legal)
        }
        .frame(width: 760, height: 640)
        .accessibilityIdentifier("settings.window")
    }

    private var generalPane: some View {
        AppSettingsPane(accessibilityIdentifier: "settings.general") {
            AppSettingsSection(title: model.text(.settingsGeneralTab)) {
                AppSettingsRow(model.text(.settingsLanguagePicker)) {
                    Picker(String(), selection: $model.appLanguage) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .labelsHidden()
                }

                AppSettingsRow(model.text(.settingsAppearancePicker)) {
                    Picker(String(), selection: $model.appearanceMode) {
                        ForEach(AppAppearanceMode.allCases) { mode in
                            Label(appearanceName(mode), systemImage: mode.systemImage)
                                .tag(mode)
                        }
                    }
                    .labelsHidden()
                }

                AppSettingsToggleRow(
                    label: model.text(AppLocalizedPhrase.developerMode),
                    isOn: $model.developerMode
                )
            }

            MemoryCacheSettingsSection(store: model.frameCacheResidencyStore)
            SupportBundleSettingsSection()
        }
    }

    private var interfacePane: some View {
        AppSettingsPane(accessibilityIdentifier: "settings.interface") {
            AppSettingsSection(title: model.text(.settingsInterfaceTab)) {
                AppSettingsRow(model.text(.settingsCanvasBackgroundPicker)) {
                    Picker(String(), selection: $model.canvasBackground) {
                        ForEach(CanvasBackground.allCases) { background in
                            Text(canvasBackgroundName(background)).tag(background)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }

                AppSettingsToggleRow(
                    label: model.text(AppLocalizedPhrase.colorClippingOverlay),
                    isOn: $model.clippingOverlayEnabled
                )

                PixelSamplerSettingsRow(
                    store: model.pixelSamplerStore,
                    language: model.appLanguage,
                    onSetEnabled: { enabled in
                        model.setPixelSamplerEnabled(enabled)
                    }
                )
            }
        }
    }

    private var workflowPane: some View {
        AppSettingsPane(accessibilityIdentifier: "settings.workflow") {
            AppSettingsSection(title: model.text(.settingsWorkflowTab)) {
                AppSettingsToggleRow(
                    label: model.text(.commandToggleScannerSimulator),
                    isOn: Binding(
                        get: { model.demoMode },
                        set: { model.toggleDemo($0) }
                    )
                )
                AppSettingsToggleRow(
                    label: model.text(AppLocalizedPhrase.developImportsAutomatically),
                    isOn: $model.developsImportsAutomatically
                )
            }

            AppSettingsSection(
                title: model.text(AppLocalizedPhrase.defaultDefectMicroSpecks)
            ) {
                AppSettingsToggleRow(
                    label: model.text(AppLocalizedPhrase.autoDefect),
                    isOn: $model.defaultAutoDefectMicroSpecks
                )
                AppSettingsToggleRow(
                    label: model.text(AppLocalizedPhrase.guidedDefect),
                    isOn: $model.defaultGuidedDefectMicroSpecks
                )
                AppSettingsHelpText(
                    model.text(AppLocalizedPhrase.defaultDefectMicroSpecksHelp)
                )
            }
        }
    }

    private var scanPane: some View {
        AppSettingsPane(accessibilityIdentifier: "settings.scan") {
            AppSettingsSection(
                title: model.text(AppLocalizedPhrase.settingsScanTab)
            ) {
                AppSettingsRow(
                    model.text(AppLocalizedPhrase.settingsDefaultScanRotationPicker)
                ) {
                    Picker(String(), selection: $model.defaultScanRotation) {
                        ForEach(ImageRotation.allCases, id: \.self) { rotation in
                            Text("\(rotation.displayName)°").tag(rotation)
                        }
                    }
                    .labelsHidden()
                }
                AppSettingsHelpText(
                    model.text(AppLocalizedPhrase.settingsDefaultScanRotationHelp)
                )
            }

            ScannerTruthSettingsSection()
        }
    }

    private var diskPane: some View {
        AppSettingsPane(accessibilityIdentifier: "settings.disk") {
            DiskStorageSettingsSection()
        }
    }

    private var exportPane: some View {
        AppSettingsPane(accessibilityIdentifier: "settings.export") {
            AppSettingsSection(title: model.text(.quickExportSection)) {
                AppSettingsRow(model.text(.settingsQuickExportFormat)) {
                    Picker(String(), selection: $model.quickExportFormat) {
                        Text("JPEG").tag(ExportFormat.jpeg)
                        Text("PNG").tag(ExportFormat.png)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }

                AppSettingsRow(model.text(.settingsQuickExportDPI)) {
                    Picker(String(), selection: $model.quickExportDPI) {
                        ForEach([0, 72, 150, 240, 300, 600], id: \.self) { dpi in
                            Text(
                                dpi == 0
                                    ? model.text(.settingsSourceDPI)
                                    : "\(dpi) dpi"
                            )
                            .tag(dpi)
                        }
                    }
                    .labelsHidden()
                }

                AppSettingsRow(model.text(.settingsQuickExportSize)) {
                    Picker(String(), selection: $model.quickExportLongEdge) {
                        ForEach([0, 1024, 2048, 4096, 6000], id: \.self) { edge in
                            Text(
                                edge == 0
                                    ? model.text(.exportFullSize)
                                    : "\(edge) \(model.text(.exportLongEdgeSuffix))"
                            )
                            .tag(edge)
                        }
                    }
                    .labelsHidden()
                }

                AppSettingsValueRow(
                    label: model.text(.settingsQuickExportFolder),
                    value: model.quickExportFolderDisplay
                )
            }

            AppSettingsSection(title: model.text(.settingsExportVerification)) {
                AppSettingsRow(model.text(.settingsExportVerification)) {
                    Picker(String(), selection: $model.exportVerificationLevel) {
                        Text(model.text(.settingsExportVerificationStandard))
                            .tag(ExportVerificationLevel.standard)
                        Text(model.text(.settingsExportVerificationStrict))
                            .tag(ExportVerificationLevel.strict)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
                AppSettingsHelpText(model.text(.settingsExportVerificationHelp))
            }

            ColorManagementSettingsSection()
        }
    }

    private var shortcutsPane: some View {
        AppSettingsPane(accessibilityIdentifier: "settings.shortcuts") {
            WorkflowShortcutsSettingsSection()
        }
    }

    private var legalPane: some View {
        AppSettingsPane(accessibilityIdentifier: "settings.legal") {
            LegalNoticeSettingsSection()
        }
    }

    private func appearanceName(_ mode: AppAppearanceMode) -> String {
        switch mode {
        case .system: model.text(.appearanceSystem)
        case .dark: model.text(.appearanceDark)
        case .light: model.text(.appearanceLight)
        }
    }

    private func canvasBackgroundName(_ background: CanvasBackground) -> String {
        switch background {
        case .black: model.text(.canvasBackgroundBlack)
        case .gray: model.text(.canvasBackgroundGray)
        case .white: model.text(.canvasBackgroundWhite)
        }
    }
}
