import SwiftUI

struct WorkflowShortcutsSettingsSection: View {
    @EnvironmentObject private var model: AppModel
    @State private var rejectedAction: WorkflowShortcutAction?
    @State private var rejectedGestureAction: WorkflowGestureModifierAction?
    @State private var recordingAction: WorkflowShortcutAction?
    @State private var selectedGroup = WorkflowShortcutGroup.library

    var body: some View {
        AppSettingsSection(
            title: model.text(.settingsShortcutsTab)
        ) {
            SegmentedPicker(
                options: WorkflowShortcutGroup.allCases,
                label: { model.text($0.titleKey) },
                selection: $selectedGroup
            )
        }

        AppSettingsSection(
            title: model.text(selectedGroup.titleKey)
        ) {
            ForEach(model.workflowShortcutActions.filter { $0.group == selectedGroup }) { action in
                shortcutRow(for: action)
            }
            if selectedGroup == .develop {
                ForEach(WorkflowGestureModifierAction.allCases) { action in
                    gestureModifierRow(for: action)
                }
            }
        }

        Section {
            AppSettingsRow(model.text(.shortcutResetAll)) {
                Button {
                    resetAllShortcuts()
                } label: {
                    Label(
                        model.text(.shortcutReset),
                        systemImage: "arrow.counterclockwise"
                    )
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func resetAllShortcuts() {
        model.resetAllWorkflowShortcuts()
        rejectedAction = nil
        rejectedGestureAction = nil
        recordingAction = nil
    }

    /// 키 없이 조합키만 거는 동작. 녹화 칸 대신 고를 수 있는 조합키 목록을 보여 준다 — 조합키만
    /// 눌렀다 떼는 것은 녹화 칸이 받지 않는다.
    private func gestureModifierRow(for action: WorkflowGestureModifierAction) -> some View {
        let current = model.gestureModifier(for: action)
        return Group {
            AppSettingsRow(action.title(in: model)) {
                HStack(spacing: 8) {
                    Picker(action.title(in: model), selection: Binding(
                        get: { current.rawValue },
                        set: { raw in
                            let accepted = model.setGestureModifier(
                                WorkflowShortcutModifiers(rawValue: raw),
                                for: action
                            )
                            rejectedGestureAction = accepted ? nil : action
                        }
                    )) {
                        ForEach(action.allowedModifiers, id: \.rawValue) { modifier in
                            Text([modifier.symbol, modifier.title(in: model)].joined(separator: " "))
                                .tag(modifier.rawValue)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity)

                    Button {
                        model.resetGestureModifier(for: action)
                        rejectedGestureAction = nil
                    } label: {
                        Label(model.text(.shortcutReset), systemImage: "arrow.uturn.backward")
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .help(model.text(.shortcutReset))
                    .accessibilityLabel(model.text(.shortcutReset))
                }
                .frame(maxWidth: .infinity)
            }

            if rejectedGestureAction == action {
                AppSettingsHelpText(
                    model.text(.shortcutInvalidOrConflict),
                    color: .red
                )
            }
        }
    }

    private func shortcutRow(for action: WorkflowShortcutAction) -> some View {
        let shortcut = model.shortcut(for: action)

        return Group {
            AppSettingsRow(action.title(in: model)) {
                HStack(spacing: 8) {
                    ShortcutRecorderField(
                        displayString: shortcut.displayString,
                        recordingPrompt: model.text(.shortcutRecordingPrompt),
                        clickToRecordHelp: model.text(.shortcutClickToRecord),
                        accessibilityLabel: action.title(in: model),
                        onStart: {
                            recordingAction = action
                            rejectedAction = nil
                        },
                        onCommit: { recorded in
                            let accepted = model.setShortcut(recorded, for: action)
                            recordingAction = nil
                            rejectedAction = accepted ? nil : action
                            return accepted
                        },
                        onCancel: {
                            recordingAction = nil
                        },
                        onInvalid: {
                            recordingAction = nil
                            rejectedAction = action
                        }
                    )
                    .frame(maxWidth: .infinity, minHeight: 30)

                    if recordingAction == action {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Button {
                        model.resetWorkflowShortcut(for: action)
                        rejectedAction = nil
                        recordingAction = nil
                    } label: {
                        Label(model.text(.shortcutReset), systemImage: "arrow.uturn.backward")
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .help(model.text(.shortcutReset))
                    .accessibilityLabel(model.text(.shortcutReset))
                }
                .frame(maxWidth: .infinity)
            }

            if rejectedAction == action {
                AppSettingsHelpText(
                    model.text(.shortcutInvalidOrConflict),
                    color: .red
                )
            }
        }
    }
}
