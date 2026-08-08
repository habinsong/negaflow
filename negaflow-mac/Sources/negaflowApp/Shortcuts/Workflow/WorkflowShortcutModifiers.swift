import Combine
import Foundation
import SwiftUI
import AppKit

struct WorkflowShortcutModifiers: OptionSet, Codable, Hashable, Sendable {
    let rawValue: Int

    init(rawValue: Int) {
        self.rawValue = rawValue
    }

    static let command = Self(rawValue: 1 << 0)
    static let shift = Self(rawValue: 1 << 1)
    static let option = Self(rawValue: 1 << 2)
    static let control = Self(rawValue: 1 << 3)

    static let editableCases: [Self] = [.command, .shift, .option, .control]

    var eventModifiers: EventModifiers {
        var result: EventModifiers = []
        if contains(.command) { result.insert(.command) }
        if contains(.shift) { result.insert(.shift) }
        if contains(.option) { result.insert(.option) }
        if contains(.control) { result.insert(.control) }
        return result
    }

    init(eventModifierFlags: NSEvent.ModifierFlags) {
        var result: WorkflowShortcutModifiers = []
        if eventModifierFlags.contains(.command) { result.insert(.command) }
        if eventModifierFlags.contains(.shift) { result.insert(.shift) }
        if eventModifierFlags.contains(.option) { result.insert(.option) }
        if eventModifierFlags.contains(.control) { result.insert(.control) }
        self = result
    }

    var symbol: String {
        let value: String
        switch self {
        case .command: value = "⌘"
        case .shift: value = "⇧"
        case .option: value = "⌥"
        case .control: value = "⌃"
        default: value = ""
        }
        return value
    }

    @MainActor
    func title(in model: AppModel) -> String {
        let fallback: String
        switch self {
        case .command: return model.text(.shortcutModifierCommand)
        case .shift: return model.text(.shortcutModifierShift)
        case .option: return model.text(.shortcutModifierOption)
        case .control: return model.text(.shortcutModifierControl)
        default:
            fallback = symbol
        }
        return fallback
    }

    var displayString: String {
        Self.editableCases
            .filter { contains($0) }
            .map(\.symbol)
            .joined()
    }
}
