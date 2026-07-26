import SwiftUI
import Chromabase

struct AppSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage(AppSettingsTab.defaultsKey)
    private var selectedTab: AppSettingsTab = .general

    var body: some View {
        TabView(selection: $selectedTab) {
            settingsForm {
                Picker(model.text(.settingsLanguagePicker), selection: $model.appLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                Picker(model.text(.settingsAppearancePicker), selection: $model.appearanceMode) {
                    ForEach(AppAppearanceMode.allCases) { mode in
                        Label(appearanceName(mode), systemImage: mode.systemImage).tag(mode)
                    }
                }
                Toggle(model.text(AppLocalizedPhrase.developerMode), isOn: $model.developerMode)
                Toggle(
                    model.text(AppLocalizedPhrase.defaultDefectMicroSpecks),
                    isOn: $model.defaultDefectMicroSpecks
                )
                .help(model.text(AppLocalizedPhrase.defaultDefectMicroSpecksHelp))
                MemoryCacheSettingsSection(store: model.frameCacheResidencyStore)
                SupportBundleSettingsSection()
            }
            .tabItem { Label(model.text(.settingsGeneralTab), systemImage: "gearshape") }
            .tag(AppSettingsTab.general)

            settingsForm {
                Picker(model.text(.settingsCanvasBackgroundPicker), selection: $model.canvasBackground) {
                    ForEach(CanvasBackground.allCases) { background in
                        Text(canvasBackgroundName(background)).tag(background)
                    }
                }
            }
            .tabItem { Label(model.text(.settingsInterfaceTab), systemImage: "sidebar.left") }
            .tag(AppSettingsTab.interface)

            settingsForm {
                Toggle(model.text(.commandToggleScannerSimulator), isOn: Binding(
                    get: { model.demoMode },
                    set: { model.toggleDemo($0) }
                ))

                ScannerTruthSettingsSection()
            }
            .tabItem { Label(model.text(.settingsWorkflowTab), systemImage: "rectangle.stack") }
            .tag(AppSettingsTab.workflow)

            settingsForm {
                Picker(model.text(.settingsDefaultScanRotationPicker), selection: $model.defaultScanRotation) {
                    ForEach(ImageRotation.allCases, id: \.self) { rotation in
                        Text("\(rotation.displayName)°").tag(rotation)
                    }
                }
                Text(model.text(.settingsDefaultScanRotationHelp))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .tabItem { Label(model.text(.settingsScanTab), systemImage: "scanner") }
            .tag(AppSettingsTab.scan)

            settingsForm {
                DiskStorageSettingsSection()
            }
            .tabItem { Label(model.text(AppLocalizedPhrase.settingsDiskTab), systemImage: "externaldrive") }
            .tag(AppSettingsTab.disk)

            settingsForm {
                Picker(model.text(.settingsQuickExportFormat), selection: $model.quickExportFormat) {
                    Text("JPEG").tag(ExportFormat.jpeg)
                    Text("PNG").tag(ExportFormat.png)
                }
                Picker(model.text(.settingsQuickExportDPI), selection: $model.quickExportDPI) {
                    ForEach([0, 72, 150, 240, 300, 600], id: \.self) { dpi in
                        Text(dpi == 0 ? model.text(.settingsSourceDPI) : "\(dpi) dpi").tag(dpi)
                    }
                }
                LabeledContent(model.text(.settingsQuickExportFolder)) {
                    Text(model.quickExportFolderDisplay)
                        .foregroundStyle(.secondary)
                }

                ColorManagementSettingsSection()
            }
            .tabItem { Label(model.text(.settingsExportTab), systemImage: "square.and.arrow.up") }
            .tag(AppSettingsTab.export)

            settingsForm {
                WorkflowShortcutsSettingsSection()
            }
            .accessibilityIdentifier("settings.shortcuts")
            .tabItem { Label(model.text(.settingsShortcutsTab), systemImage: "keyboard") }
            .tag(AppSettingsTab.shortcuts)

            settingsForm {
                LegalNoticeSettingsSection()
            }
            .tabItem { Label(model.text(.settingsLegalTab), systemImage: "doc.text.magnifyingglass") }
            .tag(AppSettingsTab.legal)
        }
        .padding(20)
        .frame(width: 760, height: 580)
    }

    private func settingsForm<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        Form {
            content()
        }
        .formStyle(.grouped)
        .padding(.top, 8)
    }

    private func appearanceName(_ mode: AppAppearanceMode) -> String {
        switch mode {
        case .system: return model.text(.appearanceSystem)
        case .dark: return model.text(.appearanceDark)
        case .light: return model.text(.appearanceLight)
        }
    }

    private func canvasBackgroundName(_ background: CanvasBackground) -> String {
        switch background {
        case .black: return model.text(.canvasBackgroundBlack)
        case .gray: return model.text(.canvasBackgroundGray)
        case .white: return model.text(.canvasBackgroundWhite)
        }
    }
}
