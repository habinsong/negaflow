import Chromabase
import SwiftUI

struct LibraryBrowserHeader: View {
    @EnvironmentObject private var model: AppModel
    @State private var showsFilters = false
    let projection: LibraryBrowserProjection
    let organizerTitle: String
    let organizerSelection: LibraryOrganizerSelection
    let usesStoredDefinition: Bool
    let effectiveSortKey: LibrarySortKey
    let effectiveSortAscending: Bool
    @Binding var quickFilters: LibraryQuickFilterState
    @Binding var viewModeRaw: String
    @Binding var sortKeyRaw: String
    @Binding var sortAscending: Bool
    @Binding var cardScale: Double
    @Binding var cullingMode: LibraryCullingMode
    let onClearAllFilters: () -> Void
    let onSelectAll: () -> Void

    // 폭 변화에 흔들리지 않는 단순 배치다. 예전에는 GeometryReader + ScrollView(.horizontal) +
    // frame(minWidth: proxy.size.width) 조합이었는데, 좌측 패널을 끄는 동안 매 프레임 proxy 가
    // 바뀌면 스크롤 콘텐츠 폭이 함께 바뀌면서 ScrollView 가 오프셋을 다시 잡는다 — 그게 헤더가
    // 좌우로 깜빡이며 튀던 원인이다. 제목이 먼저 줄고 오른쪽 컨트롤은 제자리를 지킨다(툴바 관례).
    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                Text(organizerTitle)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(model.text(
                    AppLocalizedPhrase.libraryResultCountFormat,
                    projection.matchedCount,
                    projection.sourceCount
                ))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
            }
            .layoutPriority(-1)

            if usesStoredDefinition {
                activeStoredSearchBar
                    .fixedSize(horizontal: true, vertical: false)
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                if !usesStoredDefinition {
                    filterButton
                    if quickFilters.isActive {
                        Button(action: onClearAllFilters) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(.plain)
                        .help(model.text(AppLocalizedPhrase.clearFilters))
                        .accessibilityLabel(model.text(AppLocalizedPhrase.clearFilters))
                    }
                }

                sortMenu
                LibraryCullingModePicker(
                    mode: $cullingMode,
                    selectionCount: model.actionableSelectedFrames.count
                )
                LibraryDuplicateCandidateButton(
                    orderedFrameIDs: projection.orderedFrameIDs
                )
                if cullingMode == .grid {
                    cardSizeControl
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(height: 44)
    }

    private var activeStoredSearchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: organizerSelection.isSmart ? "gearshape.2" : "magnifyingglass")
                .foregroundStyle(.secondary)
            Text(organizerTitle)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 8)
            Button(action: onSelectAll) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.text(AppLocalizedPhrase.clearFilters))
        }
        .padding(.horizontal, 9)
        .frame(minWidth: 180, idealWidth: 220, maxWidth: 260, minHeight: 28)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(Color.primary.opacity(0.12))
        }
    }

    private var filterButton: some View {
        Button {
            showsFilters.toggle()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: quickFilters.isActive
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle")
                Text(model.text(AppLocalizedPhrase.libraryFilters))
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(quickFilters.isActive ? Color.accentColor : Color.secondary)
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showsFilters, arrowEdge: .top) {
            LibraryBrowserFilterBar(
                quickFilters: $quickFilters,
                viewModeRaw: $viewModeRaw
            )
            .padding(10)
            .frame(width: 620)
        }
    }

    private var sortMenu: some View {
        Menu {
            ForEach(LibrarySortKey.allCases) { key in
                Button {
                    sortKeyRaw = key.rawValue
                } label: {
                    Text(key.displayName(language: model.appLanguage))
                }
                .accessibilitySelectionState(
                    key == sortKey,
                    selectedValue: model.accessibilityText(.selected),
                    unselectedValue: model.accessibilityText(.notSelected),
                    unselectedHint: model.accessibilityText(.select)
                )
            }
            Divider()
            Button(model.text(AppLocalizedPhrase.ascending)) {
                sortAscending = true
            }
            .accessibilitySelectionState(
                sortAscending,
                selectedValue: model.accessibilityText(.selected),
                unselectedValue: model.accessibilityText(.notSelected),
                unselectedHint: model.accessibilityText(.select)
            )
            Button(model.text(AppLocalizedPhrase.descending)) {
                sortAscending = false
            }
            .accessibilitySelectionState(
                !sortAscending,
                selectedValue: model.accessibilityText(.selected),
                unselectedValue: model.accessibilityText(.notSelected),
                unselectedHint: model.accessibilityText(.select)
            )
        } label: {
            HStack(spacing: 4) {
                Text(effectiveSortKey.displayName(language: model.appLanguage))
                    .lineLimit(1)
                Image(systemName: effectiveSortAscending ? "arrow.up" : "arrow.down")
                    .font(.caption2.weight(.semibold))
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 4)
            .frame(height: 22)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .disabled(usesStoredDefinition)
    }

    private var cardSizeControl: some View {
        HStack(spacing: 1) {
            HoverStepIconButton(
                systemName: "minus",
                text: "−",
                help: model.text(AppLocalizedPhrase.frameCardSizeHelp),
                isDisabled: cardScale <= 0.72
            ) {
                cardScale = max(0.72, cardScale - 0.08)
            }

            Button {
                cardScale = 1
            } label: {
                Text(verbatim: "\(Int((cardScale * 100).rounded()))%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 38, height: 22)
            }
            .buttonStyle(.plain)
            .help(model.text(AppLocalizedPhrase.frameCardSizeHelp))

            HoverStepIconButton(
                systemName: "plus",
                text: "+",
                help: model.text(AppLocalizedPhrase.frameCardSizeHelp),
                isDisabled: cardScale >= 1.42
            ) {
                cardScale = min(1.42, cardScale + 0.08)
            }
        }
        .help(model.text(AppLocalizedPhrase.frameCardSizeHelp))
    }

    private var sortKey: LibrarySortKey {
        LibrarySortKey(rawValue: sortKeyRaw) ?? .inputOrder
    }

}

struct LibrarySearchField: View {
    @EnvironmentObject private var model: AppModel
    @Binding var searchText: String
    let onClearSearch: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(
                model.text(AppLocalizedPhrase.librarySearchPlaceholder),
                text: $searchText
            )
            .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button(action: onClearSearch) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help(model.text(AppLocalizedPhrase.libraryClearSearch))
                .accessibilityLabel(model.text(AppLocalizedPhrase.libraryClearSearch))
            }
        }
        .padding(.horizontal, 9)
        .frame(width: LibraryViewModePicker.controlWidth, height: 28)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(Color.primary.opacity(0.12))
        }
    }
}

struct LibraryViewModePicker: View {
    static let controlWidth: CGFloat = 280

    @EnvironmentObject private var model: AppModel
    @Binding var viewModeRaw: String
    @Binding var filmTypeRaw: String
    let isDisabled: Bool

    var body: some View {
        HStack(spacing: 0) {
            ForEach(LibraryViewMode.allCases) { mode in
                if mode == .filmType {
                    Menu {
                        ForEach(FilmType.allCases, id: \.self) { filmType in
                            Button {
                                withAnimation(.snappy(duration: 0.18)) {
                                    filmTypeRaw = filmType.rawValue
                                    viewModeRaw = mode.rawValue
                                }
                            } label: {
                                if selectedFilmType == filmType {
                                    Label(
                                        filmType.displayName(language: model.appLanguage),
                                        systemImage: "checkmark"
                                    )
                                } else {
                                    Text(filmType.displayName(language: model.appLanguage))
                                }
                            }
                        }
                    } label: {
                        modeLabel(mode)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(mode.displayName(language: model.appLanguage))
                    .accessibilityValue(
                        selectedFilmType.displayName(language: model.appLanguage)
                    )
                    .accessibilitySelectionState(
                        viewMode == mode,
                        selectedValue: model.accessibilityText(.selected),
                        unselectedValue: model.accessibilityText(.notSelected),
                        unselectedHint: model.accessibilityText(.select)
                    )
                } else {
                    Button {
                        withAnimation(.snappy(duration: 0.18)) {
                            viewModeRaw = mode.rawValue
                        }
                    } label: {
                        modeLabel(mode)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(mode.displayName(language: model.appLanguage))
                    .accessibilitySelectionState(
                        viewMode == mode,
                        selectedValue: model.accessibilityText(.selected),
                        unselectedValue: model.accessibilityText(.notSelected),
                        unselectedHint: model.accessibilityText(.select)
                    )
                }
            }
        }
        .padding(2)
        .frame(width: Self.controlWidth)
        .contentShape(Capsule(style: .continuous))
        .liquidSurface(cornerRadius: 16, interactive: true)
        .disabled(isDisabled)
    }

    private var viewMode: LibraryViewMode {
        LibraryViewMode(rawValue: viewModeRaw) ?? .folders
    }

    private var selectedFilmType: FilmType {
        FilmType(rawValue: filmTypeRaw) ?? .colorNegative
    }

    private func modeLabel(_ mode: LibraryViewMode) -> some View {
        Text(mode.capsuleDisplayName(language: model.appLanguage))
            .font(.caption.weight(.semibold))
            .foregroundStyle(viewMode == mode ? Color.primary : Color.secondary)
            .lineLimit(1)
            .minimumScaleFactor(AppTypography.minimumScaleFactor)
            .frame(maxWidth: .infinity, minHeight: 28)
            .padding(.horizontal, 6)
            .background {
                if viewMode == mode {
                    Color.clear
                        .liquidSurface(cornerRadius: 14, interactive: true)
                }
            }
            .contentShape(Capsule(style: .continuous))
    }
}
