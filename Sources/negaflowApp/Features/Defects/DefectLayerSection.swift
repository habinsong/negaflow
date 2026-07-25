import SwiftUI
import Chromabase

// Defect Layer 패널(v2). 적용된 결함 제거를 원본을 덮어쓴 픽셀이 아니라 "복원 레이어" 목록으로
// 보여준다: 항목별 켜기/끄기(단일 결함 before/after), 강도, 마스크 표시, 삭제. cleaned raw 는
// 켜진 레이어만 순서대로 재적용해 만들어지므로 어떤 항목을 되돌려도 다른 항목은 유지된다.
struct DefectLayerSection: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var frame: ScanFrame
    private let visibleLayerLimit = 5
    private let estimatedLayerRowHeight: CGFloat = 54

    var body: some View {
        if !frame.defectEdits.isEmpty {
            InspectorCard {
                InspectorCardHeader(title: model.text(AppLocalizedPhrase.defectLayers), systemImage: "bandage",
                                    trailing: "\(frame.defectEdits.count)")
                layerList
                if frame.boundDefectRecipeIdentity != nil {
                    Divider()
                    HStack {
                        Spacer()
                        Button {
                            model.markDefectRecipeReviewed(frame)
                        } label: {
                            Label(
                                model.text(AppLocalizedPhrase.done),
                                systemImage: isCurrentRecipeReviewed
                                    ? "checkmark.seal.fill"
                                    : "checkmark.seal"
                            )
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .disabled(isCurrentRecipeReviewed || frame.isRemovingDefects)
                    }
                }
            }
        }
    }

    private var isCurrentRecipeReviewed: Bool {
        guard let identity = frame.boundDefectRecipeIdentity,
              let sourceIdentity = identity.sourceIdentity,
              let tracking = frame.libraryWorkflowTrackingState?.defectReviewTracking else {
            return false
        }
        return tracking.reviewedRecipeRevision == identity.revision
            && tracking.reviewedRecipeSHA256 == identity.recipeSHA256
            && tracking.reviewedSourceIdentitySHA256 == sourceIdentity.sha256
    }

    @ViewBuilder
    private var layerList: some View {
        if frame.defectEdits.count <= visibleLayerLimit {
            VStack(spacing: 4) {
                defectRows
            }
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        defectRows
                    }
                }
                .frame(maxHeight: estimatedLayerRowHeight * CGFloat(visibleLayerLimit))
                .onAppear { scrollToLatest(using: proxy) }
                .onChange(of: latestDefectEditID) { _, _ in
                    scrollToLatest(using: proxy)
                }
            }
        }
    }

    private var defectRows: some View {
        ForEach(Array(frame.defectEdits.enumerated()), id: \.element.id) { offset, item in
            DefectLayerRow(frame: frame, item: item, displayIndex: offset + 1)
                .id(item.id)
        }
    }

    private var latestDefectEditID: UUID? {
        frame.defectEdits.last?.id
    }

    private func scrollToLatest(using proxy: ScrollViewProxy) {
        guard let latestDefectEditID else { return }
        withAnimation(.snappy(duration: 0.18)) {
            proxy.scrollTo(latestDefectEditID, anchor: .bottom)
        }
    }
}

private struct DefectLayerRow: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var frame: ScanFrame
    let item: DefectEditItem
    let displayIndex: Int
    @State private var strength: Double = 1.0

    private var isMaskShown: Bool { frame.defectMaskPreviewID == item.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(verbatim: "\(displayIndex).")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, alignment: .trailing)

                // 레이어 적용 켜기/끄기 = 그 결함만의 before/after.
                Button {
                    model.setDefectEditEnabled(frame, id: item.id, enabled: !item.enabled)
                } label: {
                    Image(systemName: item.enabled ? "eye" : "eye.slash")
                        .foregroundStyle(item.enabled ? Color.primary : Color.secondary)
                }
                .buttonStyle(.borderless)
                .help(item.enabled ? model.text(AppLocalizedPhrase.disableLayer) : model.text(AppLocalizedPhrase.enableLayer))
                .disabled(frame.isRemovingDefects)

                Image(systemName: item.isBrush
                        ? "paintbrush.pointed.fill"
                        : (item.isClone ? "rectangle.on.rectangle" : "scope"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(item.title).font(.callout).lineLimit(1)
                Spacer()

                // 마스크 표시(검출 위치를 분류색으로 오버레이).
                Button {
                    frame.defectMaskPreviewID = isMaskShown ? nil : item.id
                } label: {
                    Image(systemName: "rectangle.dashed")
                        .foregroundStyle(isMaskShown ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.borderless)
                .help(isMaskShown ? model.text(AppLocalizedPhrase.hideMask) : model.text(AppLocalizedPhrase.showMask))

                Button {
                    model.removeDefectEdit(frame, id: item.id)
                } label: {
                    Image(systemName: "trash").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help(model.text(AppLocalizedPhrase.deleteLayer))
                .disabled(frame.isRemovingDefects)
            }
            HStack(spacing: 8) {
                Text(item.summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(model.text(AppLocalizedPhrase.strength)).font(.caption2).foregroundStyle(.secondary)
                // 드래그 중(live): undo 1회 푸시 + 저장 생략 + 조용한 빌드로 즉시 반영(이전 빌드는
                // 리비전 취소로 대체). 드래그 종료: 최종 커밋 + 디스크 백킹 저장.
                Slider(value: $strength, in: 0.1...1.0) { editing in
                    if editing {
                        model.beginDefectEditGesture(frame)
                    } else {
                        model.setDefectEditStrength(frame, id: item.id, strength: strength)
                    }
                }
                .frame(width: 72)
                .controlSize(.mini)
                .disabled(!item.enabled)
                .onChange(of: strength) { _, new in
                    guard abs(new - item.strength) > 1e-3 else { return }
                    model.setDefectEditStrength(frame, id: item.id, strength: new, live: true)
                }
            }
        }
        .padding(.vertical, 3)
        .opacity(item.enabled ? 1 : 0.55)
        .onAppear { strength = item.strength }
        .onChange(of: item.strength) { _, new in strength = new }
    }
}
