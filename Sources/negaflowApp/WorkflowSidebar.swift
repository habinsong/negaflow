import SwiftUI

enum WorkflowSidebarTab: String, CaseIterable, Identifiable {
    case library
    case versions
    case presets
    case output

    var id: Self { self }

    var title: String {
        switch self {
        case .library: return "Library"
        case .versions: return "Versions"
        case .presets: return "Presets"
        case .output: return "Output"
        }
    }

    var systemImage: String {
        switch self {
        case .library: return "rectangle.stack"
        case .versions: return "clock.arrow.circlepath"
        case .presets: return "slider.horizontal.below.square.and.square.filled"
        case .output: return "square.and.arrow.up"
        }
    }
}

struct WorkflowSidebar: View {
    @EnvironmentObject var model: AppModel
    @Binding var selectedTab: WorkflowSidebarTab
    let frame: ScanFrame?

    var body: some View {
        HStack(spacing: 0) {
            tabRail
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 9)

                Divider()

                Form {
                    selectedContent
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial)
        .clipped()
    }

    var tabRail: some View {
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
        .padding(.horizontal, 7)
        .frame(width: 54)
        .frame(maxHeight: .infinity)
        .background(.bar)
    }

    var header: some View {
        HStack(spacing: 7) {
            Image(systemName: selectedTab.systemImage)
                .frame(width: 16)
            Text(selectedTab.title)
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 8)
            Text(frame?.displayName ?? "No Frame")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .multilineTextAlignment(.trailing)
        }
    }

    @ViewBuilder
    var selectedContent: some View {
        switch selectedTab {
        case .library:
            ScanSection()
            if let frame {
                RollOverviewSection(frame: frame)
            } else {
                SidebarEmptyState(title: "스캔 대기", systemImage: "film")
            }
        case .versions:
            if let frame {
                VirtualCopySection(frame: frame)
                DevelopHistorySection(frame: frame)
                SnapshotSection(frame: frame)
            } else {
                SidebarEmptyState(title: "프레임 없음", systemImage: "photo.on.rectangle")
            }
        case .presets:
            if let frame {
                DevelopSettingsTransferSection(frame: frame)
                UserPresetSection(frame: frame)
            } else {
                SidebarEmptyState(title: "프레임 없음", systemImage: "photo.on.rectangle")
            }
        case .output:
            if frame != nil {
                ExportSection()
            } else {
                SidebarEmptyState(title: "내보낼 프레임 없음", systemImage: "square.and.arrow.up")
            }
        }
    }
}

private struct SidebarTabButton: View {
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
        .help(tab.title)
        .accessibilityLabel(tab.title)
    }
}

private struct RollOverviewSection: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var frame: ScanFrame

    var body: some View {
        Section {
            LabeledContent("Selected", value: frame.displayName)
            LabeledContent("Frames", value: "\(model.frames.count)")
            LabeledContent("Film", value: frame.filmType.displayName)
            LabeledContent("State", value: frame.hasDevelopedOnce ? "Developed" : "Raw")
            LabeledContent("Select", value: frame.selectionSummary)
            LabeledContent("Roll", value: selectionCountsText)
            LabeledContent("Versions", value: "\(frame.developHistory.count) history · \(frame.developSnapshots.count) snapshots")
        } header: {
            sectionHeader("Roll", systemImage: "film.stack")
        }

        Section {
            FrameSelectionControls(frame: frame)
        }
    }

    var selectionCountsText: String {
        let picked = model.frames.filter { $0.pickState == .picked }.count
        let rejected = model.frames.filter { $0.pickState == .rejected }.count
        return "\(picked) pick · \(rejected) reject"
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
