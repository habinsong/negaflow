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
        StatusBarMessageRow(
            center: model.statusCenter,
            isScanning: model.isScanning,
            leading: {
                StatusPhaseIndicator(
                    phase: model.scanPhase,
                    language: model.appLanguage,
                    errorLog: model.errorLog
                )
            },
            collapsible: {
                statusProgressSlot
                    .frame(width: 244, alignment: .leading)
            },
            trailing: {
                HStack(spacing: 10) {
                    compactFilmstripItemSizeHUD
                    bottomSortMenu
                    bottomScopeMenu
                }
            }
        )
        .padding(.horizontal, 10)
        .frame(height: statusBarHeight)
        .adaptivePanelSurface(.bar)
    }

    var bottomSortKey: LibrarySortKey {
        LibrarySortKey(rawValue: filmstripSortKeyRaw) ?? .inputOrder
    }

    var bottomFilmstripScope: FilmstripScope {
        FilmstripScope(rawValue: filmstripScopeRaw) ?? .folder
    }

    var activeDevelopInteractionScopeFrameIDs: [UUID] {
        guard selectedWorkspaceModule == .develop || selectedWorkspaceModule == .print else { return [] }
        return LibraryPresentation.sortedFrames(
            bottomFilmstripScope.filtered(model.frames, reference: model.actionableFrame),
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
            // 한 줄 텍스트로 그린다. macOS 27 SDK 의 테두리 없는 메뉴는 HStack 라벨을 아이콘이
            // 앞에 오게 다시 배치해, 원래의 "이름 ↑" 순서가 뒤집혔다.
            Text("\(Text(bottomSortKey.displayName(language: model.appLanguage))) \(Image(systemName: filmstripSortAscending ? "arrow.up" : "arrow.down"))")
            .lineLimit(1)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 4)
            .frame(height: 22)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        // macOS 27 SDK 부터 테두리 없는 메뉴가 남는 폭을 차지해 하단바 오른쪽 묶음이 흩어진다.
        // 내용 크기로 고정해 오른쪽 정렬을 지킨다.
        .fixedSize()
        .help(model.text(AppLocalizedPhrase.sortBy))
    }

    /// 필름스트립 표시 범위 — 정렬 메뉴와 같은 모양으로 바로 옆에 둔다.
    var bottomScopeMenu: some View {
        Menu {
            ForEach(FilmstripScope.allCases) { scope in
                Button {
                    filmstripScopeRaw = scope.rawValue
                } label: {
                    HStack {
                        Text(scope.displayName(language: model.appLanguage))
                        if scope == bottomFilmstripScope {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Text("\(Text(bottomFilmstripScope.displayName(language: model.appLanguage))) \(Image(systemName: "line.3.horizontal.decrease"))")
            .lineLimit(1)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 4)
            .frame(height: 22)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(model.text(AppLocalizedPhrase.filmstripScope))
        .accessibilityIdentifier("negaflow.filmstrip.scope")
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
