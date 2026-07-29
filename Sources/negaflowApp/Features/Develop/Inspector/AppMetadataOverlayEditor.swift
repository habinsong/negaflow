import SwiftUI

/// 앱 메타데이터 + 촬영 기록 편집.
///
/// 저장 버튼은 두지 않는다 — 이 앱의 다른 편집은 전부 즉시 반영되는데 여기만 버튼을 눌러야 하면
/// 눌렀는지 안 눌렀는지가 사용자 기억에 남는다. 입력이 멈추면 자동으로 반영하고, 반영 여부를
/// 헤더에 표시한다. 프레임을 바꿔도 편집 중이던 프레임에 정확히 반영한다.
struct AppMetadataOverlayEditor: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var frame: ScanFrame

    @State private var draft = AppMetadataOverlayDraft()
    @State private var storedDraft = AppMetadataOverlayDraft()
    @State private var editingFrame: ScanFrame?
    @State private var commitTask: Task<Void, Never>?
    @State private var blockedReason: String?

    /// 입력이 멈춘 뒤 반영까지 기다리는 시간. 타이핑마다 카탈로그를 건드리지 않기 위한 값이다.
    private let commitDelay = Duration.milliseconds(700)

    private var hasConflict: Bool {
        frame.appMetadataOverlay?.conflicts(with: frame.sourceMetadata) == true
    }

    private var selectionCount: Int { model.actionableSelectedFrames.count }

    var body: some View {
        InspectorCard {
            VStack(alignment: .leading, spacing: 8) {
                InspectorCardHeader(
                    title: localized(.title),
                    systemImage: "square.and.pencil",
                    trailing: statusText
                )
                TextField(localized(.fieldTitle), text: $draft.title)
                TextField(localized(.caption), text: $draft.caption)
                TextField(localized(.keywords), text: $draft.keywords)
                TextField(localized(.copyright), text: $draft.copyright)
                Divider()
                Label(localized(.filmShot), systemImage: "camera")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                FilmShotMetadataFields(draft: $draft.shot)
                if hasConflict {
                    HStack(spacing: 6) {
                        Label(localized(.conflict), systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button(localized(.resolve)) {
                            if model.resolveAppMetadataOverlayConflict(for: frame) { loadDraft() }
                        }
                    }
                    .font(.caption)
                }
                if selectionCount > 1 {
                    Button("\(localized(.applySelection)) (\(selectionCount))") {
                        applyToSelection()
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .onAppear { loadDraft() }
        .onDisappear { commitPending() }
        .onChange(of: draft) { _, _ in scheduleCommit() }
        .onChange(of: frame.id) { _, _ in
            commitPending()
            loadDraft()
        }
        .onChange(of: frame.appMetadataOverlay) { _, newValue in
            // 다른 경로(선택 적용, 롤 기록 채우기, 충돌 해소)로 바뀐 값만 받아온다. 방금 내가 저장한
            // 값이거나 편집 중이면 입력을 건드리지 않는다(커서가 튀지 않게).
            let incoming = AppMetadataOverlayDraft(newValue)
            guard incoming != storedDraft, draft == storedDraft else { return }
            draft = incoming
            storedDraft = incoming
        }
    }

    // MARK: 상태 표시

    private var statusText: String? {
        if let blockedReason { return blockedReason }
        if draft != storedDraft { return localized(.pendingSave) }
        return storedDraft == AppMetadataOverlayDraft() ? nil : localized(.saved)
    }

    // MARK: 반영

    private func loadDraft() {
        commitTask?.cancel()
        commitTask = nil
        editingFrame = frame
        draft = AppMetadataOverlayDraft(frame.appMetadataOverlay)
        storedDraft = draft
        blockedReason = nil
    }

    private func scheduleCommit() {
        guard draft != storedDraft else { return }
        commitTask?.cancel()
        let pending = draft
        let target = editingFrame
        commitTask = Task { @MainActor in
            try? await Task.sleep(for: commitDelay)
            guard !Task.isCancelled else { return }
            commit(pending, to: target)
        }
    }

    private func commitPending() {
        commitTask?.cancel()
        commitTask = nil
        guard draft != storedDraft else { return }
        commit(draft, to: editingFrame)
    }

    private func commit(_ value: AppMetadataOverlayDraft, to target: ScanFrame?) {
        guard let target else { return }
        let applied = model.applyAppMetadataOverlay(value, to: [target])
        guard target.id == frame.id else { return }
        if applied {
            storedDraft = value
            blockedReason = nil
        } else {
            blockedReason = localized(.notEditable)
        }
    }

    private func applyToSelection() {
        commitPending()
        let targets = model.actionableSelectedFrames
        guard model.applyAppMetadataOverlay(draft, to: targets) else {
            blockedReason = localized(.notEditable)
            return
        }
        storedDraft = draft
        blockedReason = nil
        model.statusMessage = "\(localized(.applySelection)): \(targets.count)"
    }

    private func localized(_ text: AppMetadataOverlayLocalizedText) -> String {
        text.resolved(language: model.appLanguage)
    }
}
