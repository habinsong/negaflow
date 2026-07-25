import SwiftUI

struct WorkflowShortcutsSettingsSection: View {
    @EnvironmentObject private var model: AppModel
    @State private var rejectedAction: WorkflowShortcutAction?
    @State private var recordingAction: WorkflowShortcutAction?
    @State private var selectedGroup = WorkflowShortcutGroup.library

    var body: some View {
        Section {
            SegmentedPicker(
                options: WorkflowShortcutGroup.allCases,
                label: { model.text($0.titleKey) },
                selection: $selectedGroup
            )
        }

        Section {
            ForEach(model.workflowShortcutActions.filter { $0.group == selectedGroup }) { action in
                shortcutRow(for: action)
            }
        } header: {
            sectionHeader(
                model.text(selectedGroup.titleKey),
                systemImage: selectedGroup.systemImage
            )
        }

        Section {
            Button {
                model.resetAllWorkflowShortcuts()
                rejectedAction = nil
                recordingAction = nil
            } label: {
                Label(model.text(.shortcutResetAll), systemImage: "arrow.counterclockwise")
            }
        }
    }

    private func shortcutRow(for action: WorkflowShortcutAction) -> some View {
        let shortcut = model.shortcut(for: action)

        return VStack(alignment: .leading, spacing: 6) {
            LabeledContent(action.title(in: model)) {
                HStack(spacing: 8) {
                    Spacer(minLength: 24)

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
                    .frame(width: 148, height: 24)

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
                    .help(model.text(.shortcutReset))
                }
            }

            if rejectedAction == action {
                Text(model.text(.shortcutInvalidOrConflict))
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}
