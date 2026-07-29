import SwiftUI

/// 롤 기록 편집. 한 롤은 같은 카메라·렌즈·필름으로 찍히므로 여기에 한 번 적으면 그 롤 프레임의
/// 비어 있는 칸이 채워진다. 프레임에 이미 적은 값은 덮지 않는다.
struct RollRecordEditor: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var frame: ScanFrame

    @State private var draft = RollRecordDraft()
    @State private var storedDraft = RollRecordDraft()
    @State private var editingRollID: UUID?
    @State private var commitTask: Task<Void, Never>?
    @State private var filledCount: Int?

    private let commitDelay = Duration.milliseconds(700)

    var body: some View {
        if let rollID = model.physicalRollID(for: frame) {
            content(rollID: rollID)
                .onAppear { load(rollID: rollID) }
                .onDisappear { commitPending() }
                .onChange(of: draft) { _, _ in scheduleCommit() }
                .onChange(of: rollID) { _, newValue in
                    commitPending()
                    load(rollID: newValue)
                }
        } else if model.allowsLibraryMutation, !frame.isPreviewScan, model.ownsFrame(frame) {
            unassignedContent
        }
    }

    /// 가져온 프레임은 롤에 속하지 않는다. 여기서 롤을 만들어야 롤 기록을 적을 수 있다.
    private var unassignedContent: some View {
        InspectorCard {
            VStack(alignment: .leading, spacing: 8) {
                InspectorCardHeader(title: localized(.rollRecord), systemImage: "film.stack")
                Text(localized(.rollMissing))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(localized(.rollCreateFromSelection)) { createRoll() }
                    .buttonStyle(.borderless)
            }
        }
    }

    private func createRoll() {
        let targets = model.actionableSelectedFrames.isEmpty
            ? [frame]
            : model.actionableSelectedFrames
        let name = frame.storageGroupName ?? frame.displayName(language: model.appLanguage)
        guard let roll = model.createPhysicalRoll(name: name, filmType: frame.filmType) else {
            return
        }
        for target in targets {
            model.moveOriginalFrameFamily(containing: target, toRollID: roll.id)
        }
    }

    private func content(rollID: UUID) -> some View {
        InspectorCard {
            VStack(alignment: .leading, spacing: 8) {
                InspectorCardHeader(
                    title: localized(.rollRecord),
                    systemImage: "film.stack",
                    trailing: model.rollName(for: frame)
                )
                TextField(localized(.rollCode), text: $draft.code)
                FilmShotMetadataFields(draft: $draft.shot, showsExposure: false)
                TextField(localized(.rollNotes), text: $draft.notes)
                Text(filledCount.map { "\(localized(.rollFilled)) \($0)" } ?? localized(.rollFillHint))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func load(rollID: UUID) {
        commitTask?.cancel()
        commitTask = nil
        editingRollID = rollID
        draft = RollRecordDraft(model.rollRecord(for: frame))
        storedDraft = draft
        filledCount = nil
    }

    private func scheduleCommit() {
        guard draft != storedDraft else { return }
        commitTask?.cancel()
        let pending = draft
        let target = editingRollID
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
        commit(draft, to: editingRollID)
    }

    private func commit(_ value: RollRecordDraft, to rollID: UUID?) {
        guard let rollID else { return }
        guard model.updateRollRecord(id: rollID, record: value.values) else { return }
        guard rollID == editingRollID else { return }
        storedDraft = value
        filledCount = model.fillFramesFromRollRecord(rollID: rollID)
    }

    private func localized(_ text: AppMetadataOverlayLocalizedText) -> String {
        text.resolved(language: model.appLanguage)
    }
}

struct RollRecordDraft: Equatable {
    var code = ""
    var shot = FilmShotDraft()
    var notes = ""

    init() {}

    init(_ record: RollRecord?) {
        code = record?.code ?? ""
        shot = FilmShotDraft(record?.shot)
        notes = record?.notes ?? ""
    }

    var values: RollRecord {
        RollRecord(code: code, shot: shot.values, notes: notes)
    }
}
