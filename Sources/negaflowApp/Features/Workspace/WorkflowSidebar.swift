import SwiftUI

enum WorkflowSidebarTab: String, CaseIterable, Identifiable {
    case library
    case files
    case versions
    case presets
    case film
    case output

    var id: Self { self }

    var textKey: AppLocalizedText {
        switch self {
        case .library: return .sidebarLibrary
        case .files: return .sidebarFiles
        case .versions: return .sidebarVersions
        case .presets: return .sidebarPresets
        case .film: return .sidebarFilm
        case .output: return .sidebarOutput
        }
    }

    var systemImage: String {
        switch self {
        case .library: return "rectangle.stack"
        case .files: return WorkflowSidebarSymbol.files
        case .versions: return "clock.arrow.circlepath"
        case .presets: return "slider.horizontal.below.square.and.square.filled"
        case .film: return "camera.filters"
        case .output: return "square.and.arrow.up"
        }
    }
}

private enum WorkflowSidebarSymbol {
    static let files = "folder"
}

struct WorkflowSidebar: View {
    @EnvironmentObject var model: AppModel
    @Binding var selectedTab: WorkflowSidebarTab
    let frame: ScanFrame?

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 300
            HStack(spacing: 0) {
                tabRail(width: compact ? 48 : 76)
                Divider()
                VStack(alignment: .leading, spacing: 0) {
                    header(showsFrameName: !compact)
                        .padding(.horizontal, compact ? 8 : 12)
                        .padding(.top, 12)
                        .padding(.bottom, 9)

                    Divider()

                    switch selectedTab {
                    case .library:
                        LibrarySourceSection(
                            visibleFolderPaths: selectedFrameFolderPaths
                        )
                    case .files:
                        LibrarySourceSection(content: .files, showsDevelopDefaults: false)
                    default:
                        Form {
                            selectedContent
                        }
                        .formStyle(.grouped)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .adaptivePanelSurface(.regular)
    }

    private var selectedFrameFolderPaths: Set<String> {
        guard let frame else { return [] }
        return [
            LibraryPresentation.normalizedFolderPath(
                LibraryPresentation.folderURL(for: frame)
            ),
        ]
    }

    func tabRail(width: CGFloat) -> some View {
        VStack(spacing: 7) {
            ForEach(WorkflowSidebarTab.allCases) { tab in
                SidebarTabButton(
                    tab: tab,
                    isSelected: selectedTab == tab,
                    action: { withAnimation(.snappy(duration: 0.18)) { selectedTab = tab } }
                )
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 10)
        .padding(.horizontal, max(3, (width - 32) / 2))
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .adaptivePanelSurface(.bar)
    }

    func header(showsFrameName: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: selectedTab.systemImage)
                .frame(width: 16)
            Text(model.text(selectedTab.textKey))
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 8)
            if showsFrameName {
                Text(frame?.displayName(language: model.appLanguage) ?? model.text(.noFrame))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(AppTypography.minimumScaleFactor)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    @ViewBuilder
    var selectedContent: some View {
        switch selectedTab {
        case .library, .files:
            EmptyView()
        case .versions:
            if let frame {
                VirtualCopySection(frame: frame)
                DevelopHistorySection(frame: frame)
                SnapshotSection(frame: frame)
            } else {
                SidebarEmptyState(title: model.text(.noFrame), systemImage: "photo.on.rectangle")
            }
        case .presets:
            if let frame {
                DevelopSettingsTransferSection(frame: frame)
                UserPresetSection(frame: frame)
            } else {
                SidebarEmptyState(title: model.text(.noFrame), systemImage: "photo.on.rectangle")
            }
        case .film:
            if let frame {
                FilmEmulationSection(frame: frame)
            } else {
                SidebarEmptyState(title: model.text(.noFrame), systemImage: "camera.filters")
            }
        case .output:
            if frame != nil {
                ExportSection()
            } else {
                SidebarEmptyState(title: model.text(.noExportFrame), systemImage: "square.and.arrow.up")
            }
        }
    }
}

private struct SidebarTabButton: View {
    @EnvironmentObject private var model: AppModel
    let tab: WorkflowSidebarTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: tab.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 32, height: 32)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(model.text(tab.textKey))
        .accessibilityLabel(model.text(tab.textKey))
        .accessibilitySelectionState(
            isSelected,
            selectedValue: model.accessibilityText(.selected),
            unselectedValue: model.accessibilityText(.notSelected),
            unselectedHint: model.accessibilityText(.select)
        )
    }
}

private struct SidebarEmptyState: View {
    let title: String
    let systemImage: String

    var body: some View {
        Section {
            ContentUnavailableView(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, minHeight: 92)
                .foregroundStyle(.secondary)
        }
    }
}

/// 좌측탭 모든 섹션이 공유하는 Form 섹션 헤더 — 아이콘 + 제목 + 우측 보조 텍스트.
@ViewBuilder
func sectionHeader(_ title: String, systemImage: String, trailing: String? = nil) -> some View {
    HStack(spacing: 6) {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
        if let trailing {
            Spacer(minLength: 8)
            Text(trailing)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
    .textCase(nil)
}
