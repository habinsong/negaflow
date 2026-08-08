import Combine
import Foundation
import SwiftUI
import AppKit

enum WorkflowShortcutRecordingResult: Equatable {
    case commit(WorkflowShortcut)
    case cancel
    case invalid
}

enum WorkflowShortcutRecorder {
    static func shortcutFromKeyRelease(
        key: String?,
        modifiers: WorkflowShortcutModifiers
    ) -> WorkflowShortcutRecordingResult {
        let normalized = WorkflowShortcut.normalizedKey(key ?? "")
        guard !normalized.isEmpty else { return .invalid }
        guard normalized != "escape" && normalized != "\u{1b}" else { return .cancel }

        let shortcut = WorkflowShortcut(key: normalized, modifiers: modifiers)
        return shortcut.isValid ? .commit(shortcut) : .invalid
    }

    static func shortcut(from event: NSEvent) -> WorkflowShortcutRecordingResult {
        let key = event.charactersIgnoringModifiers ?? event.characters
        let modifiers = WorkflowShortcutModifiers(eventModifierFlags: event.modifierFlags)
        return shortcutFromKeyRelease(key: key, modifiers: modifiers)
    }
}
