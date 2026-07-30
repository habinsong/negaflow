import SwiftUI

enum PrintWorkspaceSidebarTab: String, CaseIterable, Identifiable {
    case files
    case export

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .files: "folder"
        case .export: "square.and.arrow.up"
        }
    }
}

struct PrintWorkspaceSidebar: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var settingsStore: PrintWorkspaceSettingsStore
    @Binding var selectedTab: PrintWorkspaceSidebarTab
    @Binding var selectedFolderID: String?

    var body: some View {
        HStack(spacing: 0) {
            tabRail
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider()
                selectedContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .adaptivePanelSurface(.regular)
        .clipped()
    }

    private var tabRail: some View {
        VStack(spacing: 7) {
            ForEach(PrintWorkspaceSidebarTab.allCases) { tab in
                PrintSidebarTabButton(
                    systemImage: tab.systemImage,
                    title: title(for: tab),
                    isSelected: selectedTab == tab
                ) {
                    withAnimation(.snappy(duration: 0.18)) { selectedTab = tab }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 10)
        .padding(.horizontal, 7)
        .frame(width: 76)
        .frame(maxHeight: .infinity)
        .adaptivePanelSurface(.bar)
    }

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: selectedTab.systemImage)
                .frame(width: 16)
            Text(title(for: selectedTab))
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 8)
            Text(model.actionableFrame?.displayName(language: model.appLanguage) ?? model.text(.noFrame))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(AppTypography.minimumScaleFactor)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 9)
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedTab {
        case .files:
            LibrarySourceSection(
                content: .files,
                showsDevelopDefaults: false,
                selectedFolderID: $selectedFolderID
            )
        case .export:
            Form {
                ExportSection(
                    usesPaperLayout: true,
                    usesCompositeLayout: settingsStore.layoutMode != .singleImage,
                    onExport: {
                        model.exportPrintSelectionToFolder(
                            settings: model.printCompositionSettings(dpi: model.exportDPI)
                        )
                    },
                    onQuickExport: {
                        model.quickExportPrintSelection(
                            settings: model.printCompositionSettings(dpi: model.quickExportDPI)
                        )
                    }
                )
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
    }

    private func title(for tab: PrintWorkspaceSidebarTab) -> String {
        switch tab {
        case .files: model.text(AppLocalizedPhrase.libraryFiles)
        case .export: model.text(.exportSection)
        }
    }
}

private struct PrintSidebarTabButton: View {
    @EnvironmentObject private var model: AppModel
    let systemImage: String
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 32, height: 32)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .accessibilitySelectionState(
            isSelected,
            selectedValue: model.accessibilityText(.selected),
            unselectedValue: model.accessibilityText(.notSelected),
            unselectedHint: model.accessibilityText(.select)
        )
    }
}
