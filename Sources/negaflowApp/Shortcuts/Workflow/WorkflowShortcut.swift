import Combine
import Foundation
import SwiftUI
import AppKit

struct WorkflowShortcut: Codable, Equatable, Hashable, Sendable {
    private static let deleteKeyName = "delete"
    private static let deleteDisplayName = "Delete"

    var key: String
    var modifiers: WorkflowShortcutModifiers

    init(key: String, modifiers: WorkflowShortcutModifiers) {
        self.key = Self.normalizedKey(key)
        self.modifiers = modifiers
    }

    var isValid: Bool {
        Self.isValidKey(key)
    }

    var keyEquivalent: KeyEquivalent {
        switch key {
        case Self.deleteKeyName:
            return .delete
        default:
            guard let character = key.first else { return KeyEquivalent(" ") }
            return KeyEquivalent(character)
        }
    }

    var displayString: String {
        modifiers.displayString + Self.displayKey(key)
    }

    var signature: String {
        "\(modifiers.rawValue):\(key)"
    }

    static func normalizedKey(_ value: String) -> String {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch key {
        case "\u{7f}", "\u{8}", "backspace", "delete":
            return deleteKeyName
        default:
            return key
        }
    }

    static func isValidKey(_ value: String) -> Bool {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789[]\\-=;'/,.`")
        let key = normalizedKey(value)
        return key == deleteKeyName || (key.count == 1 && key.allSatisfy { allowed.contains($0) })
    }

    static func displayKey(_ value: String) -> String {
        switch normalizedKey(value) {
        case deleteKeyName: return deleteDisplayName
        default: return value.uppercased()
        }
    }
}
