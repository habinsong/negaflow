import Combine
import Foundation
import SwiftUI
import AppKit

@MainActor
final class WorkflowShortcutStore: ObservableObject {
    private enum Keys {
        static let overrides = "workflow.shortcuts.overrides"
        static let gestureOverrides = "workflow.gestureModifiers.overrides"
        static let legacyGuidedDefectAction = "semiAutoDefectTool"
    }

    private let defaults: UserDefaults

    @Published private var overrides: [WorkflowShortcutAction: WorkflowShortcut] = [:] {
        didSet { saveOverrides() }
    }

    @Published private var gestureOverrides: [WorkflowGestureModifierAction: WorkflowShortcutModifiers] = [:] {
        didSet { saveGestureOverrides() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        overrides = Self.loadOverrides(from: defaults)
        gestureOverrides = Self.loadGestureOverrides(from: defaults)
    }

    func gestureModifier(for action: WorkflowGestureModifierAction) -> WorkflowShortcutModifiers {
        gestureOverrides[action] ?? action.defaultModifier
    }

    /// 조합키 하나만 받는다. 다른 조합키 동작과 같은 키면 거절한다 — 기준선과 격자가 같은 키를
    /// 쓰면 격자만 보고 싶어도 드래그가 기준선이 되어 각도가 바뀐다.
    @discardableResult
    func setGestureModifier(
        _ modifier: WorkflowShortcutModifiers,
        for action: WorkflowGestureModifierAction
    ) -> Bool {
        guard action.allowedModifiers.contains(modifier) else { return false }
        guard !WorkflowGestureModifierAction.allCases.contains(where: {
            $0 != action && gestureModifier(for: $0) == modifier
        }) else { return false }
        if modifier == action.defaultModifier {
            gestureOverrides.removeValue(forKey: action)
        } else {
            gestureOverrides[action] = modifier
        }
        return true
    }

    /// 기본값으로 돌린다. 다른 동작이 그 기본 키를 이미 쓰고 있으면 그쪽도 기본값으로 돌린다 —
    /// 두 동작이 한 키를 나눠 갖는 상태를 만들지 않는다.
    func resetGestureModifier(for action: WorkflowGestureModifierAction) {
        gestureOverrides.removeValue(forKey: action)
        for other in WorkflowGestureModifierAction.allCases where other != action
            && gestureModifier(for: other) == action.defaultModifier {
            gestureOverrides.removeValue(forKey: other)
        }
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
        gestureOverrides.removeAll()
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

    private static func loadGestureOverrides(
        from defaults: UserDefaults
    ) -> [WorkflowGestureModifierAction: WorkflowShortcutModifiers] {
        guard let data = defaults.data(forKey: Keys.gestureOverrides),
              let decoded = try? JSONDecoder().decode([String: Int].self, from: data) else {
            return [:]
        }
        var loaded: [WorkflowGestureModifierAction: WorkflowShortcutModifiers] = [:]
        for action in WorkflowGestureModifierAction.allCases {
            guard let raw = decoded[action.rawValue] else { continue }
            let modifier = WorkflowShortcutModifiers(rawValue: raw)
            guard action.allowedModifiers.contains(modifier) else { continue }
            loaded[action] = modifier
        }
        // 손으로 고친 설정이 두 동작에 같은 키를 걸었으면 버리고 기본값으로 둔다.
        let effective = WorkflowGestureModifierAction.allCases.map { loaded[$0] ?? $0.defaultModifier }
        guard Set(effective.map(\.rawValue)).count == effective.count else { return [:] }
        return loaded
    }

    private func saveGestureOverrides() {
        let payload = gestureOverrides.reduce(into: [String: Int]()) { result, element in
            result[element.key.rawValue] = element.value.rawValue
        }
        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: Keys.gestureOverrides)
    }

    private func saveOverrides() {
        let payload = overrides.reduce(into: [String: WorkflowShortcut]()) { result, element in
            result[element.key.rawValue] = element.value
        }
        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: Keys.overrides)
    }
}
