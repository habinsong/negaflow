import SwiftUI

private struct AccessibilitySelectionTraitModifier: ViewModifier {
    let isSelected: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isSelected {
            content.accessibilityAddTraits(.isSelected)
        } else {
            content.accessibilityRemoveTraits(.isSelected)
        }
    }
}

extension View {
    func accessibilitySelectionTrait(_ isSelected: Bool) -> some View {
        modifier(AccessibilitySelectionTraitModifier(isSelected: isSelected))
    }

    func accessibilitySelectionState(
        _ isSelected: Bool,
        selectedValue: String,
        unselectedValue: String,
        selectedHint: String? = nil,
        unselectedHint: String? = nil
    ) -> some View {
        accessibilitySelectionTrait(isSelected)
            .accessibilityValue(isSelected ? selectedValue : unselectedValue)
            .accessibilityHint(isSelected ? (selectedHint ?? "") : (unselectedHint ?? ""))
    }

    func accessibilityToggleState(
        _ isOn: Bool,
        onValue: String,
        offValue: String,
        onHint: String? = nil,
        offHint: String? = nil
    ) -> some View {
        accessibilityValue(isOn ? onValue : offValue)
            .accessibilityHint(isOn ? (onHint ?? "") : (offHint ?? ""))
    }

    @ViewBuilder
    func accessibilityActiveState(
        _ isActive: Bool?,
        activeValue: String,
        inactiveValue: String,
        activateHint: String,
        deactivateHint: String
    ) -> some View {
        if let isActive {
            accessibilitySelectionState(
                isActive,
                selectedValue: activeValue,
                unselectedValue: inactiveValue,
                selectedHint: deactivateHint,
                unselectedHint: activateHint
            )
        } else {
            self
        }
    }
}
