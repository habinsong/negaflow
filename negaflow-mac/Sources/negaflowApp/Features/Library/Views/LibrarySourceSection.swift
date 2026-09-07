import SwiftUI
import Chromabase

enum LibrarySourceContent {
    case combined
    case importing
    case files
}

struct LibrarySourceSection: View {
    @EnvironmentObject var model: AppModel
    var content = LibrarySourceContent.combined
    var showsDevelopDefaults = true
    var orderedResultFrameIDs: [UUID]? = nil
    var selectedFolderID: Binding<String?> = .constant(nil)
    var visibleFolderPaths: Set<String>? = nil
    var scrollsFrameListInternally = false

    @ViewBuilder
    var body: some View {
        switch content {
        case .combined:
            GeometryReader { proxy in
                Form {
                    importSections(availableWidth: proxy.size.width)
                    Section {
                        LibraryFolderTreeView(
                            orderedResultFrameIDs: orderedResultFrameIDs,
                            selectedFolderID: selectedFolderID,
                            visibleFolderPaths: visibleFolderPaths,
                            frameListMaxHeight: scrollsFrameListInternally
                                ? max(96, proxy.size.height * 0.36)
                                : nil
                        )
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .contextMenu { newFolderButton }
            }
        case .importing:
            importContent
        case .files:
            filesContent
        }
    }

    private var importContent: some View {
        Form {
            importSections()
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func importSections(availableWidth: CGFloat? = nil) -> some View {
        Section {
            importActionBar
                .frame(maxWidth: .infinity)
        } header: {
            HStack(spacing: 8) {
                sectionHeader(model.text(.importSection), systemImage: "square.and.arrow.down")
                Spacer(minLength: 8)
                LibraryImportProgressStatus(store: model.libraryImportProgressStore)
            }
        }

        if model.showScannerControls {
            ScannerControlsSection()
        }

        if showsDevelopDefaults {
            DevelopDefaultsSection(availableWidth: availableWidth)
        }
    }

    private var filesContent: some View {
        ScrollView {
            LibraryFolderTreeView(
                orderedResultFrameIDs: orderedResultFrameIDs,
                selectedFolderID: selectedFolderID,
                visibleFolderPaths: visibleFolderPaths
            )
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contextMenu {
            newFolderButton
        }
    }

    private var newFolderButton: some View {
        Button(model.text(AppLocalizedPhrase.newFolder)) {
            model.presentCreateLibraryFolder(
                in: model.defaultLibraryFolderCreationParent(
                    selectedFolderID: selectedFolderID.wrappedValue
                )
            )
        }
    }

    private var importActionBar: some View {
        HStack(spacing: 0) {
            ImportGlassAction(
                title: model.text(AppLocalizedPhrase.importImageShort),
                systemImage: "photo.badge.plus",
                action: model.presentImportPanel
            )
            importDivider
            ImportGlassAction(
                title: model.text(AppLocalizedPhrase.importFolderShort),
                systemImage: "folder.badge.plus",
                action: model.presentImportFolderPanel
            )
            importDivider
            ImportGlassAction(
                title: model.text(AppLocalizedPhrase.scannerLabel),
                systemImage: "scanner",
                action: {
                    withAnimation(.snappy(duration: 0.18)) {
                        model.presentScannerSetup()
                    }
                }
            )
        }
        .padding(2)
        .liquidSurface(cornerRadius: 16, interactive: true)
    }

    private var importDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: 1, height: 16)
            .padding(.horizontal, 2)
    }
}

/// 가져오기 헤더 오른쪽에 붙는 진행 표시 — 진행 바 + % + 완료/전체.
private struct LibraryImportProgressStatus: View {
    @ObservedObject var store: LibraryImportProgressStore

    @ViewBuilder
    var body: some View {
        if let progress = store.progress {
            LibraryTaskProgressView(progress: progress, barWidth: 54)
                .accessibilityIdentifier("negaflow.import.progress")
                .transition(.opacity)
        }
    }
}

private struct ImportGlassAction: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(AppTypography.minimumScaleFactor)
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .padding(.horizontal, 6)
                .background(
                    Color.primary.opacity(isHovered ? 0.12 : 0),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
