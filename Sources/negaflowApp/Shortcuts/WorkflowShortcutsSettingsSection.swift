import SwiftUI

struct WorkflowShortcutsSettingsSection: View {
    @EnvironmentObject private var model: AppModel
    @State private var rejectedAction: WorkflowShortcutAction?
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
        recordingAction = nil
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
