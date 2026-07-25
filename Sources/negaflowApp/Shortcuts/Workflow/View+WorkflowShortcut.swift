import Combine
import Foundation
import SwiftUI
import AppKit

extension View {
    func workflowKeyboardShortcut(_ shortcut: WorkflowShortcut) -> some View {
        keyboardShortcut(shortcut.keyEquivalent, modifiers: shortcut.modifiers.eventModifiers)
    }
}
