import SwiftUI
import Chromabase
import CoreImage
import AppKit

extension AppModel {
    func rebuildCleanedRaw(
        _ frame: ScanFrame,
        recipeSnapshot suppliedSnapshot: DefectRecipeSnapshot? = nil,
        persist: Bool = true,
        quiet: Bool = false,
        preloadedOriginal: CGImage? = nil
    ) {
        let edits = frame.defectEdits
        if edits.isEmpty {
            frame.cleanRawRevision += 1
            frame.cleanRawTask?.cancel()
            discardCleanedRaw(frame)
            Task { await developFrame(frame) }
            return
        }
        guard let recipeSnapshot = suppliedSnapshot ?? refreshDefectRecipeState(
            frame,
            advanceRevision: frame.defectRecipeIdentity == nil,
            persist: true
        ) else { return }
        runCleanedRawBuild(frame, editsToApply: edits, totalEditCount: edits.count,
                           preloadedBase: nil, baseDiskURL: nil, baseIdentity: nil,
                           fromOriginal: true, preloadedOriginal: preloadedOriginal,
                           recipeSnapshot: recipeSnapshot,
                           persist: persist, quiet: quiet)
    }

    /// cleaned raw 빌드 코어. fromOriginal=true면 원본 raw에 editsToApply(=전체) 순차 적용,
    /// false면 베이스(preloadedBase → 없으면 baseDiskURL)에 editsToApply만 적용.
    /// 레이어는 캐시 패치가 있으면 합성만, 없으면 계산(그 시점 베이스를 flatten해 입력) 후 캐시를
    /// 커밋에 실어 보낸다. 풀해상도 flatten 은 빌드당 1회(+캐시 미스 시 필요분)다.
    /// - persist: 커밋 후 디스크 백킹(TIFF) 저장 여부(비동기). 슬라이더 live 는 건너뛴다.
    /// - quiet: 스피너/상태 메시지 억제(드래그 중 UI 비활성화 방지).

}
