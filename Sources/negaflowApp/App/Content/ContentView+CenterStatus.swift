import SwiftUI
import AppKit
import Chromabase
import ScannerKit
import CoreImage
import UniformTypeIdentifiers

extension ContentView {
    // MARK: center pane — 캔버스 + 상태바
    @ViewBuilder
    var centerPane: some View {
        VStack(spacing: 0) {
            ZStack {
                model.canvasBackground.color
                if let frame = model.actionableFrame {
                    CanvasView(
                        frame: frame,
                        cropMode: cropModeBinding(for: frame),
                        brushMode: brushModeBinding(for: frame),
                        regionDefectMode: regionDefectModeBinding(for: frame),
                        cloneStampMode: cloneStampModeBinding(for: frame),
                        basePickerMode: basePickerModeBinding(for: frame)
                    )
                        .id(frame.id)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("negaflow.canvas")
                        .accessibilityValue(frame.hasDevelopedOnce ? "developed" : "pending")
                } else if model.isScanning {
                    Color.clear
                } else {
                    ContentUnavailableView {
                        Label(model.text(.emptyCanvasTitle), systemImage: "photo.badge.plus")
                    } description: {
                        Text(model.text(.emptyCanvasDescription))
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .overlay(alignment: .bottom) {
                if model.isScanning {
                    ScanProgressOverlay()
                        .allowsHitTesting(false)
                        .padding(.bottom, 18)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if isFilmstripVisible {
                WorkspaceFilmstrip()
            }
            statusBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: status bar — 하단, 한 줄
    var statusBar: some View {
        ZStack {
            HStack(spacing: 10) {
                StatusPhaseIndicator(
                    phase: model.scanPhase,
                    language: model.appLanguage,
                    errorLog: model.errorLog
                )
                statusProgressSlot
                    .frame(width: 244, alignment: .leading)
                Spacer()
                compactFilmstripItemSizeHUD
                bottomSortMenu
            }
            CenterStatusMessageOverlay(
                center: model.statusCenter,
                isScanning: model.isScanning
            )
        }
        .padding(.horizontal, 10)
        .frame(height: statusBarHeight)
        .adaptivePanelSurface(.bar)
    }

    var bottomSortKey: LibrarySortKey {
        LibrarySortKey(rawValue: filmstripSortKeyRaw) ?? .inputOrder
    }

    var activeDevelopInteractionScopeFrameIDs: [UUID] {
        guard selectedWorkspaceModule == .develop || selectedWorkspaceModule == .print else { return [] }
        return LibraryPresentation.sortedFrames(
            model.frames,
            key: bottomSortKey,
            ascending: filmstripSortAscending
        ).map(\.id)
    }

    func synchronizeDevelopInteractionScope() {
        guard selectedWorkspaceModule == .develop || selectedWorkspaceModule == .print else { return }
        model.updateInteractionScope(activeDevelopInteractionScopeFrameIDs)
    }

    var bottomSortMenu: some View {
        Menu {
            ForEach(LibrarySortKey.allCases) { key in
                Button {
                    filmstripSortKeyRaw = key.rawValue
                } label: {
                    HStack {
                        Text(key.displayName(language: model.appLanguage))
                        if key == bottomSortKey {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            Divider()
            Button(model.text(AppLocalizedPhrase.ascending)) { filmstripSortAscending = true }
            Button(model.text(AppLocalizedPhrase.descending)) { filmstripSortAscending = false }
        } label: {
            HStack(spacing: 4) {
                Text(bottomSortKey.displayName(language: model.appLanguage))
                    .lineLimit(1)
                Image(systemName: filmstripSortAscending ? "arrow.up" : "arrow.down")
                    .font(.caption2.weight(.semibold))
            }
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 4)
            .frame(height: 22)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help(model.text(AppLocalizedPhrase.sortBy))
    }

    var compactFilmstripItemSizeHUD: some View {
        let effectiveScale = FilmstripSizing.effectiveItemScale(
            filmstripItemScale,
            filmstripHeight: filmstripHeight
        )
        let maximumScale = FilmstripSizing.maximumEffectiveItemScale(
            currentItemScale: filmstripItemScale,
            filmstripHeight: filmstripHeight
        )
        return HStack(spacing: 1) {
            HoverStepIconButton(
                systemName: "minus",
                text: "−",
                help: model.text(AppLocalizedPhrase.frameCardSizeHelp),
                isDisabled: effectiveScale <= FilmstripSizing.minimumItemScale
            ) {
                filmstripItemScale = max(
                    FilmstripSizing.minimumItemScale,
                    effectiveScale - 0.08
                )
            }

            Button {
                filmstripItemScale = 1
            } label: {
                Text("\(Int((effectiveScale * 100).rounded()))%")
                    .font(.caption2.monospacedDigit())
                    .frame(width: 32, height: 22)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(model.text(AppLocalizedPhrase.frameCardSizeHelp))

            HoverStepIconButton(
                systemName: "plus",
                text: "+",
                help: model.text(AppLocalizedPhrase.frameCardSizeHelp),
                isDisabled: effectiveScale >= maximumScale
            ) {
                filmstripItemScale = min(maximumScale, effectiveScale + 0.08)
            }
        }
        .help(model.text(AppLocalizedPhrase.frameCardSizeHelp))
    }

}

/// 상태 메시지 텍스트 + 자동 dismiss. StatusMessageCenter 를 직접 관찰하므로 메시지 갱신은
/// 이 뷰만 다시 그린다(ContentView 전역 무효화 없음 — 관찰 경계 축소 1단계).
/// isScanning 은 여전히 AppModel 발행이라 부모가 갱신해 파라미터로 내려온다.
struct CenterStatusMessageOverlay: View {
    @ObservedObject var center: StatusMessageCenter
    let isScanning: Bool
    @State private var visible = false
    @State private var dismissTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            if visible {
                Text(center.message)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(AppTypography.minimumScaleFactor)
                    .allowsTightening(true)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
                    .padding(.horizontal, 170)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .onChange(of: center.message) { _, _ in scheduleDismissal() }
        .onChange(of: isScanning) { _, _ in scheduleDismissal() }
        .onDisappear { dismissTask?.cancel() }
    }

    private func scheduleDismissal() {
        dismissTask?.cancel()
        guard !center.message.isEmpty else {
            visible = false
            return
        }
        visible = true
        guard !isScanning else { return }
        let message = center.message
        dismissTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled, center.message == message else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                visible = false
            }
        }
    }
}
