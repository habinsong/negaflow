import SwiftUI
import Chromabase
import CoreImage
import AppKit

extension AppModel {

    /// 사용자가 칠한 스트로크(표시 좌표)를 변형 전 raw 정규좌표로 변환해 브러시 레이어로 누적한다.
    func applyDefectStrokes(_ displayStrokes: [DefectStroke], to frame: ScanFrame) {
        guard !displayStrokes.isEmpty else { return }
        let transform = frame.imageTransform
        let mapped = displayStrokes.map { stroke in
            DefectStroke(points: stroke.points.map { transform.displayUnitToBase($0) },
                         thickness: stroke.thickness)
        }
        let item = DefectEditItem(edit: .brush(mapped),
                                  title: text(AppLocalizedPhrase.grainMendBrushEditTitleFormat, mapped.count),
                                  summary: text(AppLocalizedPhrase.brushEditSummary),
                                  preview: [], baseSize: nil)
        appendDefectEdit(item, to: frame)
    }

    /// 새 레이어(브러시/가이드)를 히스토리에 추가하고 cleaned raw를 갱신한다 — 두 결함 제거의 공통 진입점.
    @discardableResult
    func appendDefectEdit(_ item: DefectEditItem, to frame: ScanFrame) -> Bool {
        let previousRecipeIdentity = frame.defectRecipeIdentity
        let previousRecipeRevision = frame.defectRecipeRevision
        let previousWorkflowTrackingState = frame.libraryWorkflowTrackingState
        let previousUndoCount = frame.defectEditUndoStack.count
        frame.defectEditUndoStack.append(frame.makeDefectEditUndoSnapshot())
        frame.defectEdits.append(item)
        guard let recipeSnapshot = refreshDefectRecipeState(
            frame,
            advanceRevision: true,
            persist: true
        ) else {
            frame.defectEdits.removeLast()
            if frame.defectEditUndoStack.count > previousUndoCount {
                frame.defectEditUndoStack.removeLast()
            }
            frame.defectRecipeRevision = previousRecipeRevision
            frame.defectRecipeIdentity = previousRecipeIdentity
            frame.libraryWorkflowTrackingState = previousWorkflowTrackingState
            invalidateLibraryQueryContext()
            scheduleLibrarySave()
            return false
        }

        // 증분 적용: 커밋된 메모리 베이스의 적용 스탬프가 현재 편집 리스트의 접두(prefix)와 그대로
        // 일치하면, 원본부터 전부 다시 합성하는 대신 아직 안 담긴 편집(suffix)만 그 위에 적용한다.
        // 커밋은 원자적이라 빌드가 진행 중이어도 베이스는 오염되지 않는다 — 진행 중 빌드는 취소되고
        // suffix 빌드가 그 몫까지 이어받는다(연속 브러시/가이드 N회가 원본 재디코드 없이 쌓인다).
        // brush/region 모두 칠한/지정한 영역 밖을 건드리지 않으므로 결과가 전체 재빌드와 동일하다.
        let stamps = frame.cleanedRawAppliedStamps
        if let memoryBase = frame.cleanedRawImage,
           let memoryBaseIdentity = frame.cleanedRawMemoryIdentity,
           memoryBaseIdentity.sourceIdentity != nil,
           stamps.count < frame.defectEdits.count,
           stamps.elementsEqual(frame.defectEdits.prefix(stamps.count).lazy.map(\.appliedStamp)) {
            let suffix = Array(frame.defectEdits[stamps.count...])
            if suffix.count == 1 {
                // 즉시 반응 경로용 "직전 베이스" 캡처: 새 레이어(=마지막)의 강도/켜기/삭제가 이
                // 베이스 위에서 패치 합성만으로 끝난다.
                frame.cleanedRawPreviousImage = memoryBase
                frame.cleanedRawPreviousEditCount = frame.defectEdits.count - 1
                frame.cleanedRawPreviousIdentity = memoryBaseIdentity
            } else {
                invalidatePreviousBase(frame)
            }
            runCleanedRawBuild(frame, editsToApply: suffix, totalEditCount: frame.defectEdits.count,
                               preloadedBase: memoryBase, baseDiskURL: nil,
                               baseIdentity: memoryBaseIdentity,
                               fromOriginal: false, recipeSnapshot: recipeSnapshot)
            return true
        }
        invalidatePreviousBase(frame)
        // 메모리 베이스가 없으면(축출 직후 등) 직전 커밋의 디스크 백킹에 새 편집 1개만 증분 적용.
        let canIncrementFromDisk = frame.cleanRawTask == nil
            && frame.cleanedRawEditCount == frame.defectEdits.count - 1
            && previousRecipeIdentity != nil
            && frame.cleanedRawImage == nil
            && frame.cleanedRawDiskURL != nil
            && frame.cleanedRawDiskIdentity == previousRecipeIdentity
        if canIncrementFromDisk {
            runCleanedRawBuild(frame, editsToApply: [item], totalEditCount: frame.defectEdits.count,
                               preloadedBase: nil, baseDiskURL: frame.cleanedRawDiskURL,
                               baseIdentity: previousRecipeIdentity,
                               fromOriginal: false, recipeSnapshot: recipeSnapshot)
        } else {
            // 첫 편집(방금 추가한 1개뿐)이고 영역 결함 제거 세션이 검출용으로 원본을 이미 풀해상도로
            // 굳혀 뒀다면 그 디코드를 재사용한다 — 첫 "제거"의 원본 재디코드(대형 TIFF/RAW에서
            // 수 초)를 없앤다. 조건이 곧 안전성이다: 편집 0개 상태(메모리/디스크 cleaned raw 없음)
            // 에서 굳힌 세션 raw = 원본이고, revision 일치가 굳힌 뒤의 소스 교체/재빌드를 배제한다.
            let sessionOriginal: CGImage? = (frame.defectEdits.count == 1
                && frame.cleanedRawImage == nil
                && frame.cleanedRawDiskURL == nil
                && frame.defectSessionRawRevision == frame.cleanRawRevision)
                ? frame.defectSessionRaw
                : nil
            rebuildCleanedRaw(frame, recipeSnapshot: recipeSnapshot,
                              preloadedOriginal: sessionOriginal)
        }
        return true
    }

    // MARK: Defect Layer 편집(v2) — 켜기/끄기·강도·삭제.
    // 마지막 레이어는 "직전 베이스 + 캐시 패치" 즉시 경로, 그 외는 원본부터 재빌드(순차 합성 정합).

    /// 강도 슬라이더 제스처 시작: undo 를 1회만 푸시한다(드래그 중 live 갱신은 푸시하지 않음).

}
