import Combine
import Foundation
import SwiftUI
import AppKit

@MainActor
final class WorkflowShortcutStore: ObservableObject {
    private enum Keys {
        static let overrides = "workflow.shortcuts.overrides"
        static let legacyGuidedDefectAction = "semiAutoDefectTool"
    }

    private let defaults: UserDefaults

    @Published private var overrides: [WorkflowShortcutAction: WorkflowShortcut] = [:] {
        didSet { saveOverrides() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        overrides = Self.loadOverrides(from: defaults)
    }

    func shortcut(for action: WorkflowShortcutAction) -> WorkflowShortcut {
        overrides[action] ?? action.defaultShortcut
    }

    @discardableResult
    func setShortcut(_ shortcut: WorkflowShortcut, for action: WorkflowShortcutAction) -> Bool {
        let normalized = WorkflowShortcut(key: shortcut.key, modifiers: shortcut.modifiers)
        guard normalized.isValid else { return false }
        guard !hasConflict(normalized, excluding: action) else { return false }

        if normalized == action.defaultShortcut {
            overrides.removeValue(forKey: action)
        } else {
            overrides[action] = normalized
        }
        return true
    }

    func resetShortcut(for action: WorkflowShortcutAction) {
        overrides.removeValue(forKey: action)
    }

    func resetAll() {
        overrides.removeAll()
    }

    private func hasConflict(_ shortcut: WorkflowShortcut, excluding action: WorkflowShortcutAction) -> Bool {
        WorkflowShortcutAction.allCases.contains { candidate in
            candidate != action && self.shortcut(for: candidate).signature == shortcut.signature
        }
    }

    private static func loadOverrides(from defaults: UserDefaults) -> [WorkflowShortcutAction: WorkflowShortcut] {
        guard let data = defaults.data(forKey: Keys.overrides),
              let decoded = try? JSONDecoder().decode([String: WorkflowShortcut].self, from: data) else {
            return [:]
        }

        var loaded: [WorkflowShortcutAction: WorkflowShortcut] = [:]
        for action in WorkflowShortcutAction.allCases {
            let shortcut = decoded[action.rawValue]
                ?? (action == .guidedDefectTool ? decoded[Keys.legacyGuidedDefectAction] : nil)
            guard let shortcut, shortcut.isValid else { continue }
            guard loaded.values.allSatisfy({ $0.signature != shortcut.signature }) else { continue }
            loaded[action] = shortcut
        }
        return loaded
    }

    private func saveOverrides() {
        let payload = overrides.reduce(into: [String: WorkflowShortcut]()) { result, element in
            result[element.key.rawValue] = element.value
        }
        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: Keys.overrides)
    }
}
