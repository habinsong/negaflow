import SwiftUI

struct LibraryBrowserFilterBar: View {
    @EnvironmentObject private var model: AppModel
    @Binding var quickFilters: LibraryQuickFilterState
    @Binding var viewModeRaw: String

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                LibraryFilterToggle(
                    title: model.text(AppLocalizedPhrase.filterCurrentRoll),
                    systemImage: "film",
                    isOn: $quickFilters.currentRoll
                )
                ratingFilterMenu
                LibraryFilterToggle(
                    title: model.text(AppLocalizedPhrase.picked),
                    systemImage: "flag.fill",
                    isOn: $quickFilters.picked
                )
                LibraryFilterToggle(
                    title: model.text(AppLocalizedPhrase.rejected),
                    systemImage: "xmark.octagon.fill",
                    isOn: $quickFilters.rejected
                )
                LibraryFilterToggle(
                    title: model.text(AppLocalizedPhrase.libraryOffline),
                    systemImage: "externaldrive.badge.questionmark",
                    isOn: offlineFilterBinding
                )
                .disabled(viewMode == .offline)
                LibraryFilterToggle(
                    title: model.text(AppLocalizedPhrase.filterInfrared),
                    systemImage: "wave.3.right",
                    isOn: $quickFilters.infrared
                )
                LibraryFilterToggle(
                    title: model.text(AppLocalizedPhrase.filterDefectRecipe),
                    systemImage: "bandage",
                    isOn: $quickFilters.defectRecipe
                )
                LibraryFilterToggle(
                    title: model.text(AppLocalizedPhrase.filterUnvalidatedProfile),
                    systemImage: "checkmark.seal",
                    isOn: $quickFilters.unvalidatedProfile
                )
                LibraryFilterToggle(
                    title: model.text(AppLocalizedPhrase.filterMetadataUnknown),
                    systemImage: "doc.questionmark",
                    isOn: $quickFilters.metadataUnknown
                )
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private var ratingFilterMenu: some View {
        Menu {
            Button(model.text(AppLocalizedPhrase.all)) {
                quickFilters.minimumRating = nil
            }
            .accessibilitySelectionState(
                quickFilters.minimumRating == nil,
                selectedValue: model.accessibilityText(.selected),
                unselectedValue: model.accessibilityText(.notSelected),
                unselectedHint: model.accessibilityText(.select)
            )
            Divider()
            ForEach(1...5, id: \.self) { rating in
                Button(model.text(AppLocalizedPhrase.filterMinimumRatingFormat, rating)) {
                    quickFilters.minimumRating = rating
                }
                .accessibilitySelectionState(
                    quickFilters.minimumRating == rating,
                    selectedValue: model.accessibilityText(.selected),
                    unselectedValue: model.accessibilityText(.notSelected),
                    unselectedHint: model.accessibilityText(.select)
                )
            }
        } label: {
            Label(
                ratingFilterTitle,
                systemImage: quickFilters.minimumRating == nil ? "star" : "star.fill"
            )
            .font(.caption.weight(.medium))
            .foregroundStyle(quickFilters.minimumRating == nil ? Color.secondary : Color.accentColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .background(
            quickFilters.minimumRating == nil ? Color.clear : Color.accentColor.opacity(0.12),
            in: RoundedRectangle(cornerRadius: 6)
        )
    }

    private var viewMode: LibraryViewMode {
        LibraryViewMode(rawValue: viewModeRaw) ?? .folders
    }

    private var offlineFilterBinding: Binding<Bool> {
        Binding(
            get: { quickFilters.offline || viewMode == .offline },
            set: { value in
                guard viewMode != .offline else { return }
                quickFilters.offline = value
            }
        )
    }

    private var ratingFilterTitle: String {
        guard let minimumRating = quickFilters.minimumRating else {
            return model.text(AppLocalizedPhrase.rating)
        }
        return model.text(AppLocalizedPhrase.filterMinimumRatingFormat, minimumRating)
    }

}

private struct LibraryFilterToggle: View {
    let title: String
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.medium))
                .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    isOn ? Color.accentColor.opacity(0.12) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .contentShape(Rectangle())
        }
        .toggleStyle(.button)
        .buttonStyle(.plain)
        // 켜짐은 배경색으로 이미 드러난다. 포커스 링까지 그리면 막대에서 첫 항목만 파란 테두리를
        // 두른 채로 남아, 켜져 있는 필터처럼 보인다.
        .focusEffectDisabled()
        .fixedSize()
    }
}
