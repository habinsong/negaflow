import SwiftUI
import AppKit

struct ShortcutRecorderField: NSViewRepresentable {
    let displayString: String
    let recordingPrompt: String
    let clickToRecordHelp: String
    let accessibilityLabel: String
    let onStart: () -> Void
    let onCommit: (WorkflowShortcut) -> Bool
    let onCancel: () -> Void
    let onInvalid: () -> Void

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton()
        button.configure(
            displayString: displayString,
            recordingPrompt: recordingPrompt,
            clickToRecordHelp: clickToRecordHelp,
            accessibilityLabel: accessibilityLabel,
            onStart: onStart,
            onCommit: onCommit,
            onCancel: onCancel,
            onInvalid: onInvalid
        )
        return button
    }

    func updateNSView(_ nsView: ShortcutRecorderButton, context: Context) {
        nsView.configure(
            displayString: displayString,
            recordingPrompt: recordingPrompt,
            clickToRecordHelp: clickToRecordHelp,
            accessibilityLabel: accessibilityLabel,
            onStart: onStart,
            onCommit: onCommit,
            onCancel: onCancel,
            onInvalid: onInvalid
        )
    }
}

final class ShortcutRecorderButton: NSButton {
    private var displayString = ""
    private var recordingPrompt = ""
    private var pendingShortcut: WorkflowShortcut?
    private var eventMonitor: Any?
    private var isRecordingShortcut = false
    private var onStart: () -> Void = {}
    private var onCommit: (WorkflowShortcut) -> Bool = { _ in false }
    private var onCancel: () -> Void = {}
    private var onInvalid: () -> Void = {}

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setButtonType(.momentaryChange)
        bezelStyle = .rounded
        isBordered = true
        focusRingType = .exterior
        font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            stopRecording()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        true
    }

    func configure(
        displayString: String,
        recordingPrompt: String,
        clickToRecordHelp: String,
        accessibilityLabel: String,
        onStart: @escaping () -> Void,
        onCommit: @escaping (WorkflowShortcut) -> Bool,
        onCancel: @escaping () -> Void,
        onInvalid: @escaping () -> Void
    ) {
        self.displayString = displayString
        self.recordingPrompt = recordingPrompt
        self.onStart = onStart
        self.onCommit = onCommit
        self.onCancel = onCancel
        self.onInvalid = onInvalid
        toolTip = clickToRecordHelp
        setAccessibilityLabel(accessibilityLabel)
        if !isRecordingShortcut {
            title = displayString
        }
    }

    override func mouseDown(with event: NSEvent) {
        startRecording()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecordingShortcut else {
            super.keyDown(with: event)
            return
        }

        handleKeyDown(event)
    }

    override func keyUp(with event: NSEvent) {
        guard isRecordingShortcut else {
            super.keyUp(with: event)
            return
        }

        handleKeyUp(event)
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecordingShortcut else {
            super.flagsChanged(with: event)
            return
        }

        handleFlagsChanged(event)
    }

    override func cancelOperation(_ sender: Any?) {
        cancelRecording()
    }

    private func startRecording() {
        isRecordingShortcut = true
        pendingShortcut = nil
        title = recordingPrompt
        window?.makeFirstResponder(self)
        installEventMonitor()
        onStart()
    }

    private func handleKeyDown(_ event: NSEvent) {
        switch WorkflowShortcutRecorder.shortcut(from: event) {
        case .commit(let shortcut):
            pendingShortcut = shortcut
            title = shortcut.displayString
        case .cancel:
            cancelRecording()
        case .invalid:
            NSSound.beep()
        }
    }

    private func handleKeyUp(_ event: NSEvent) {
        let shortcut: WorkflowShortcut?
        if let pendingShortcut {
            shortcut = pendingShortcut
        } else if case .commit(let recorded) = WorkflowShortcutRecorder.shortcut(from: event) {
            shortcut = recorded
        } else {
            shortcut = nil
        }

        guard let shortcut else {
            finishRecording()
            onInvalid()
            return
        }

        stopRecording()
        if onCommit(shortcut) {
            title = shortcut.displayString
        } else {
            title = displayString
            onInvalid()
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let modifiers = WorkflowShortcutModifiers(eventModifierFlags: event.modifierFlags)
        title = modifiers.displayString.isEmpty ? recordingPrompt : modifiers.displayString + recordingPrompt
    }

    private func installEventMonitor() {
        removeEventMonitor()
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard let self, self.isRecordingShortcut else { return event }
            guard event.window == self.window || self.window?.isKeyWindow == true else { return event }

            switch event.type {
            case .keyDown:
                self.handleKeyDown(event)
            case .keyUp:
                self.handleKeyUp(event)
            case .flagsChanged:
                self.handleFlagsChanged(event)
            default:
                return event
            }
            return nil
        }
    }

    private func cancelRecording() {
        finishRecording()
        onCancel()
    }

    private func finishRecording() {
        stopRecording()
        title = displayString
    }

    private func stopRecording() {
        isRecordingShortcut = false
        pendingShortcut = nil
        removeEventMonitor()
    }

    private func removeEventMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }
}
