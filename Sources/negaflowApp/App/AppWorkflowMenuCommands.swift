import SwiftUI
import Chromabase

struct AppWorkflowMenuCommands: Commands {
    @ObservedObject var model: AppModel

    var body: some Commands {
        CommandMenu(model.text(.menuLibrary)) {
            Button(model.text(.commandImportImages)) {
                model.performWorkflowShortcutAction(.importImages)
            }
            .workflowKeyboardShortcut(model.shortcut(for: .importImages))

            Button(model.text(AppLocalizedPhrase.importFolder)) {
                model.performWorkflowShortcutAction(.importFolder)
            }
            .workflowKeyboardShortcut(model.shortcut(for: .importFolder))

            Button(model.text(.commandRefreshLibrary)) {
                model.performWorkflowShortcutAction(.refreshLibrary)
            }
            .workflowKeyboardShortcut(model.shortcut(for: .refreshLibrary))

            Button(model.text(.loadScanner)) {
                model.performWorkflowShortcutAction(.loadScanner)
            }
            .workflowKeyboardShortcut(model.shortcut(for: .loadScanner))

            Divider()

            Button(model.cullingText(.grid)) {
                model.performWorkflowShortcutAction(.libraryGrid)
            }
            .workflowKeyboardShortcut(model.shortcut(for: .libraryGrid))

            Button(model.cullingText(.compare)) {
                model.performWorkflowShortcutAction(.libraryCompare)
            }
            .workflowKeyboardShortcut(model.shortcut(for: .libraryCompare))

            Button(model.cullingText(.survey)) {
                model.performWorkflowShortcutAction(.librarySurvey)
            }
            .workflowKeyboardShortcut(model.shortcut(for: .librarySurvey))
        }

        CommandMenu(model.text(.menuPhoto)) {
            Button(model.text(AppLocalizedPhrase.previousFrame)) {
                model.performWorkflowShortcutAction(.previousPhoto)
            }
            .workflowKeyboardShortcut(model.shortcut(for: .previousPhoto))
            .disabled(!model.canPerformWorkflowShortcutAction(.previousPhoto))

            Button(model.text(AppLocalizedPhrase.nextFrame)) {
                model.performWorkflowShortcutAction(.nextPhoto)
            }
            .workflowKeyboardShortcut(model.shortcut(for: .nextPhoto))
            .disabled(!model.canPerformWorkflowShortcutAction(.nextPhoto))

            Divider()

            Button(model.text(.commandPick)) {
                model.performWorkflowShortcutAction(.pickPhoto)
            }
            .workflowKeyboardShortcut(model.shortcut(for: .pickPhoto))
            .disabled(!model.canPerformWorkflowShortcutAction(.pickPhoto))

            Button(model.text(AppLocalizedPhrase.clearPick)) {
                model.performWorkflowShortcutAction(.clearPick)
            }
            .workflowKeyboardShortcut(model.shortcut(for: .clearPick))
            .disabled(!model.canPerformWorkflowShortcutAction(.clearPick))

            Button(model.text(.commandReject)) {
                model.performWorkflowShortcutAction(.rejectPhoto)
            }
            .workflowKeyboardShortcut(model.shortcut(for: .rejectPhoto))
            .disabled(!model.canPerformWorkflowShortcutAction(.rejectPhoto))

            Button(model.text(.commandDeletePhoto), role: .destructive) {
                model.performWorkflowShortcutAction(.deletePhoto)
            }
            .workflowKeyboardShortcut(model.shortcut(for: .deletePhoto))
            .disabled(!model.canPerformWorkflowShortcutAction(.deletePhoto))

            Divider()

            Button(model.text(AppLocalizedPhrase.resetRating)) {
                model.performWorkflowShortcutAction(.rateZero)
            }
            .workflowKeyboardShortcut(model.shortcut(for: .rateZero))
            .disabled(!model.canPerformWorkflowShortcutAction(.rateZero))

            ForEach(1...5, id: \.self) { value in
                let action = WorkflowShortcutAction.ratingAction(value)
                Button(model.text(AppLocalizedPhrase.starHelpFormat, value)) {
                    model.performWorkflowShortcutAction(action)
                }
                .workflowKeyboardShortcut(model.shortcut(for: action))
                .disabled(!model.canPerformWorkflowShortcutAction(action))
            }

            Divider()

            Button(model.text(AppLocalizedPhrase.virtualCopy)) {
                model.performWorkflowShortcutAction(.createVirtualCopy)
            }
            .workflowKeyboardShortcut(model.shortcut(for: .createVirtualCopy))
            .disabled(!model.canPerformWorkflowShortcutAction(.createVirtualCopy))

            Button(model.text(.commandCopyDevelopSettings)) {
                model.performWorkflowShortcutAction(.copyDevelopSettings)
            }
            .workflowKeyboardShortcut(model.shortcut(for: .copyDevelopSettings))
            .disabled(!model.canPerformWorkflowShortcutAction(.copyDevelopSettings))

            Button(model.text(.commandPasteDevelopSettings)) {
                model.performWorkflowShortcutAction(.pasteDevelopSettings)
            }
            .workflowKeyboardShortcut(model.shortcut(for: .pasteDevelopSettings))
            .disabled(!model.canPerformWorkflowShortcutAction(.pasteDevelopSettings))

            Divider()

            Button(model.text(AppLocalizedPhrase.rotateLeft)) {
                model.performWorkflowShortcutAction(.rotateLeft)
            }
            .workflowKeyboardShortcut(model.shortcut(for: .rotateLeft))
            .disabled(!model.canPerformWorkflowShortcutAction(.rotateLeft))

            Button(model.text(AppLocalizedPhrase.rotateRight)) {
                model.performWorkflowShortcutAction(.rotateRight)
            }
            .workflowKeyboardShortcut(model.shortcut(for: .rotateRight))
            .disabled(!model.canPerformWorkflowShortcutAction(.rotateRight))

            Button(model.text(AppLocalizedPhrase.flipHorizontal)) {
                model.performWorkflowShortcutAction(.flipHorizontal)
            }
            .workflowKeyboardShortcut(model.shortcut(for: .flipHorizontal))
            .disabled(!model.canPerformWorkflowShortcutAction(.flipHorizontal))

            Button(model.text(AppLocalizedPhrase.flipVertical)) {
                model.performWorkflowShortcutAction(.flipVertical)
            }
            .workflowKeyboardShortcut(model.shortcut(for: .flipVertical))
            .disabled(!model.canPerformWorkflowShortcutAction(.flipVertical))
        }

        CommandMenu(model.text(.menuDevelop)) {
            Button(model.text(.commandAutoTone)) {
                model.performWorkflowShortcutAction(.autoTone)
            }
            .workflowKeyboardShortcut(model.shortcut(for: .autoTone))
            .disabled(!model.canPerformWorkflowShortcutAction(.autoTone))

            Button(model.text(.commandAutoWhiteBalance)) {
                model.performWorkflowShortcutAction(.autoWhiteBalance)
            }
            .workflowKeyboardShortcut(model.shortcut(for: .autoWhiteBalance))
            .disabled(!model.canPerformWorkflowShortcutAction(.autoWhiteBalance))

            Toggle(
                model.text(AppLocalizedPhrase.autoColor),
                isOn: shortcutToggle(
                    action: .toggleAutoColor,
                    value: model.actionableFrame?.params.autoNeutralBalance == true
                )
            )
            .workflowKeyboardShortcut(model.shortcut(for: .toggleAutoColor))
            .disabled(!model.canPerformWorkflowShortcutAction(.toggleAutoColor))

            Toggle(
                model.text(AppLocalizedPhrase.autoLevels),
                isOn: shortcutToggle(
                    action: .toggleAutoLevels,
                    value: model.actionableFrame?.params.autoLevels == true
                )
            )
            .workflowKeyboardShortcut(model.shortcut(for: .toggleAutoLevels))
            .disabled(!model.canPerformWorkflowShortcutAction(.toggleAutoLevels))

            Toggle(
                model.text(AppLocalizedPhrase.noiseReduction),
                isOn: shortcutToggle(
                    action: .toggleNoiseReduction,
                    value: (model.actionableFrame?.params.noiseReduction ?? 0) > 1e-3
                )
            )
            .workflowKeyboardShortcut(model.shortcut(for: .toggleNoiseReduction))
            .disabled(!model.canPerformWorkflowShortcutAction(.toggleNoiseReduction))

            Divider()

            Menu(model.text(AppLocalizedPhrase.process)) {
                ForEach(FilmType.allCases, id: \.self) { filmType in
                    let action = WorkflowShortcutAction.developmentProcessAction(filmType)
                    Button {
                        model.performWorkflowShortcutAction(action)
                    } label: {
                        // 디지털 사진을 고른 상태에서는 같은 계열 필름 프로세스에 체크하지 않는다.
                        if model.activeDevelopmentProcess == .film(filmType) {
                            Label(filmType.developmentProcessName, systemImage: "checkmark")
                        } else {
                            Text(filmType.developmentProcessName)
                        }
                    }
                    .workflowKeyboardShortcut(model.shortcut(for: action))
                }
            }

            Menu(model.text(AppLocalizedPhrase.target)) {
                ForEach(DevelopTarget.allCases, id: \.self) { target in
                    let action = WorkflowShortcutAction.developTargetAction(target)
                    Button {
                        model.performWorkflowShortcutAction(action)
                    } label: {
                        if (model.actionableFrame?.params.developTarget ?? model.developTarget) == target {
                            Label(
                                target.displayName(language: model.appLanguage),
                                systemImage: "checkmark"
                            )
                        } else {
                            Text(target.displayName(language: model.appLanguage))
                        }
                    }
                    .workflowKeyboardShortcut(model.shortcut(for: action))
                }
            }

            Divider()

            Button(model.text(AppLocalizedPhrase.cropArea)) {
                model.performWorkflowShortcutAction(.cropTool)
            }
            .workflowKeyboardShortcut(model.shortcut(for: .cropTool))
            .disabled(!model.canPerformWorkflowShortcutAction(.cropTool))

            Button(model.text(AppLocalizedPhrase.pickBase)) {
                model.performWorkflowShortcutAction(.basePickerTool)
            }
            .workflowKeyboardShortcut(model.shortcut(for: .basePickerTool))
            .disabled(!model.canPerformWorkflowShortcutAction(.basePickerTool))

            Menu(model.text(AppLocalizedPhrase.inspectorTabDefect)) {
                ForEach([
                    WorkflowShortcutAction.autoDefectTool,
                    .guidedDefectTool,
                    .brushDefectTool,
                    .cloneStampTool,
                ]) { action in
                    Button(action.title(in: model)) {
                        model.performWorkflowShortcutAction(action)
                    }
                    .workflowKeyboardShortcut(model.shortcut(for: action))
                    .disabled(!model.canPerformWorkflowShortcutAction(action))
                }
            }

            Divider()

            Button(model.text(.commandResetAdjustments)) {
                model.performWorkflowShortcutAction(.resetAdjustments)
            }
            .workflowKeyboardShortcut(model.shortcut(for: .resetAdjustments))
            .disabled(!model.canPerformWorkflowShortcutAction(.resetAdjustments))

            Button(model.text(AppLocalizedPhrase.compareSplitVertical)) {
                model.performWorkflowShortcutAction(.toggleBeforeAfter)
            }
            .workflowKeyboardShortcut(model.shortcut(for: .toggleBeforeAfter))
            .disabled(!model.canPerformWorkflowShortcutAction(.toggleBeforeAfter))
        }

        CommandMenu(model.text(.menuScanner)) {
            Button(model.text(.commandDetectScanners)) {
                model.performWorkflowShortcutAction(.detectScanners)
            }
            .workflowKeyboardShortcut(model.shortcut(for: .detectScanners))
            .disabled(model.isDetecting || model.isScanning)

            Toggle(model.text(.commandToggleScannerSimulator), isOn: Binding(
                get: { model.demoMode },
                set: { model.toggleDemo($0) }
            ))
            .workflowKeyboardShortcut(model.shortcut(for: .toggleScannerSimulator))

            Divider()

            Button(model.text(.commandPreviewScan)) {
                model.performWorkflowShortcutAction(.previewScan)
            }
            .workflowKeyboardShortcut(model.shortcut(for: .previewScan))
            .disabled(!model.canPreview)

            Button(model.text(.commandScanFrame)) {
                model.performWorkflowShortcutAction(.scanFrame)
            }
            .workflowKeyboardShortcut(model.shortcut(for: .scanFrame))
            .disabled(!model.canScan)

            if model.usesFlatbedRegionWorkflow {
                Divider()

                Button(model.text(AppLocalizedPhrase.flatbedAddFrame)) {
                    model.performWorkflowShortcutAction(.addFlatbedFrame)
                }
                .workflowKeyboardShortcut(model.shortcut(for: .addFlatbedFrame))
                .disabled(!model.canPerformWorkflowShortcutAction(.addFlatbedFrame))

                Button(model.text(AppLocalizedPhrase.flatbedRemoveFrame)) {
                    model.performWorkflowShortcutAction(.removeFlatbedFrame)
                }
                .workflowKeyboardShortcut(model.shortcut(for: .removeFlatbedFrame))
                .disabled(!model.canPerformWorkflowShortcutAction(.removeFlatbedFrame))
            }
        }

        CommandMenu(model.text(.menuExport)) {
            Button(model.text(.commandQuickExport)) {
                model.performWorkflowShortcutAction(.quickExport)
            }
            .workflowKeyboardShortcut(model.shortcut(for: .quickExport))
            .disabled(!model.canQuickExportSelection(for: model.activeWorkspaceModule))

            Button(model.text(.commandExport)) {
                model.performWorkflowShortcutAction(.exportPhoto)
            }
            .workflowKeyboardShortcut(model.shortcut(for: .exportPhoto))
            .disabled(!model.canExportSelection(for: model.activeWorkspaceModule))
        }
    }

    private func shortcutToggle(
        action: WorkflowShortcutAction,
        value: Bool
    ) -> Binding<Bool> {
        Binding(
            get: { value },
            set: { _ in model.performWorkflowShortcutAction(action) }
        )
    }
}
