import SwiftUI
import Chromabase
import CoreImage
import AppKit

extension AppModel {
    func runCleanedRawBuild(_ frame: ScanFrame, editsToApply: [DefectEditItem],
                                    totalEditCount: Int, preloadedBase: CGImage?,
                                    baseDiskURL: URL?, baseIdentity: DefectRecipeIdentity?,
                                    fromOriginal: Bool,
                                    preloadedOriginal: CGImage? = nil,
                                    recipeSnapshot: DefectRecipeSnapshot,
                                    persist: Bool = true, quiet: Bool = false) {
        frame.cleanRawRevision += 1
        let revision = frame.cleanRawRevision
        frame.cleanRawTask?.cancel()
        frame.cleanedRawPersistTask?.cancel()
        frame.cleanedRawPersistTask = nil

        let rawURL = frame.rawScanURL
        let frameID = frame.id
        let sourceKind = frame.sourceKind
        // 커밋될 픽셀이 담게 될 편집 접두(totalEditCount개)의 현재 상태 스탬프.
        let appliedStamps = frame.defectEdits.prefix(totalEditCount).map(\.appliedStamp)
        let cachedPatchEditID = frame.defectEdits.prefix(totalEditCount).last?.id
        // 증분 합성 캔버스(프레임 상주). 편집마다 풀프레임 flatten 대신 패치 rect 만 그린다.
        let existingCanvas = frame.cleanedRawCanvas
        if !quiet {
            frame.isRemovingDefects = true
            statusMessage = text(AppLocalizedPhrase.removingDefectsStatus)
        }
        // 결함 제거 픽셀을 다시 만드는 구간. 내보내기가 이 재빌드를 기다리는 경우가 있어
        // 원본부터의 전체 재계산인지, 몇 초인지가 로그에 남아야 진단이 된다.
        let trace = AppDiagnostics.start(
            fromOriginal ? .cleanedRawRebuild : .cleanedRawBuild,
            category: .defects
        )
        let task = Task.detached(priority: .userInitiated) {
            guard let sourceIdentity = try? AppModel.defectSourceIdentity(for: rawURL) else {
                await self.finishFailedCleanedRawBuild(
                    frame,
                    revision: revision,
                    quiet: quiet
                )
                return
            }
            if recipeSnapshot.identity.sourceIdentity.map({ $0 != sourceIdentity }) == true
                || (!fromOriginal && baseIdentity?.sourceIdentity.map({ $0 != sourceIdentity }) == true) {
                await self.recoverFromChangedDefectSource(
                    frame,
                    revision: revision,
                    expectedRecipeIdentity: recipeSnapshot.identity,
                    quiet: quiet
                )
                return
            }
            guard recipeSnapshot.identity.sourceIdentity == nil
                    || recipeSnapshot.identity.sourceIdentity == sourceIdentity,
                  let boundSnapshot = try? self.bindDefectRecipeSnapshot(
                      recipeSnapshot,
                      to: sourceIdentity
                  ),
                  !Task.isCancelled else {
                await self.finishFailedCleanedRawBuild(
                    frame,
                    revision: revision,
                    quiet: quiet
                )
                return
            }
            // 풀해상도 디코딩·중간 비트맵은 autoreleasepool 안에서 처리해 산출물 외에는 즉시 해제한다.
            let built: (cleaned: CGImage, patches: [UUID: [DefectPatch]], canvas: CleanedRawCanvas?)? = autoreleasepool {
                let inputCG: CGImage?
                if !fromOriginal, let pre = preloadedBase {
                    guard baseIdentity?.sourceIdentity == sourceIdentity else { return nil }
                    inputCG = pre                                   // 증분/즉시 경로: 메모리 베이스 재사용
                } else if !fromOriginal, let url = baseDiskURL {
                    guard let baseIdentity,
                          baseIdentity.sourceIdentity == sourceIdentity,
                          CleanedRawCacheFile.isOwnedCacheURL(url, frameID: frameID)
                    else { return nil }
                    inputCG = decodeCleanedRaw(url)                 // 증분: 세션이 만든 디스크 백킹에서 복원
                } else if let preloadedOriginal {
                    // 첫 편집: 영역 결함 제거 세션이 검출용으로 이미 굳혀 둔 원본 디코드를 재사용한다
                    // — 첫 "제거"에서 원본 TIFF/RAW 풀 디코드+렌더를 통째로 건너뛴다. 유효성
                    // (편집 0개에서의 원본, revision 일치)은 호출측이 보장한다.
                    inputCG = preloadedOriginal
                } else {
                    let engine = ChromabaseEngine()                // 전체: 원본 raw 디코드
                    // 가져온 파일은 develop 과 동일 로더(방향·색 일치). 스캐너 TIFF는 기존 경로.
                    let rawCI = sourceKind == .importedFile
                        ? engine.loadImportedImage(rawURL)
                        : engine.loadScannerImage(rawURL)
                    if let rawCI, !Task.isCancelled {
                        inputCG = cleanedRawContext.createCGImage(rawCI, from: rawCI.extent,
                                                                  format: .RGBA16, colorSpace: linearColorSpace)
                    } else { inputCG = nil }
                }
                guard let inputCG, !Task.isCancelled else { return nil }
                // 레이어를 순서대로 합성한다. 패치 계산은 CIImage 체인에서 필요한 국소 창만
                // 렌더하고(레이어별 풀 flatten 없음), 최종 픽셀은 캔버스에 패치 rect 만 블릿한
                // CoW 스냅샷으로 만든다 — 편집 비용이 이미지 면적이 아니라 결함 크기에 비례한다.
                var working = CIImage(cgImage: inputCG, options: [.colorSpace: linearColorSpace])
                var dirty = false
                var computed: [UUID: [DefectPatch]] = [:]
                var applied: [(patch: DefectPatch, strength: Double)] = []
                for item in editsToApply {
                    if Task.isCancelled { return nil }
                    guard item.enabled, item.strength > 1e-3 else { continue }
                    let patches: [DefectPatch]
                    if let cached = item.cachedPatches {
                        patches = cached
                    } else {
                        guard let fresh = computeDefectPatches(item.edit, base: working,
                                                               pixelWidth: inputCG.width,
                                                               pixelHeight: inputCG.height,
                                                               shouldCancel: { Task.isCancelled })
                        else { return nil }
                        patches = fresh
                        if item.id == cachedPatchEditID { computed[item.id] = fresh }
                    }
                    for p in patches {
                        working = p.composited(over: working, strength: item.strength,
                                               colorSpace: linearColorSpace)
                        applied.append((p, item.strength))
                        dirty = true
                    }
                }
                if Task.isCancelled { return nil }
                guard dirty else { return (inputCG, computed, nil) }
                let canvas = (existingCanvas?.width == inputCG.width
                              && existingCanvas?.height == inputCG.height)
                    ? existingCanvas
                    : CleanedRawCanvas(width: inputCG.width, height: inputCG.height)
                if let canvas, let composed = canvas.composite(base: inputCG, patches: applied) {
                    return (composed, computed, canvas)
                }
                // 폴백: 캔버스 생성/합성 실패 시 기존 CI 풀 flatten (결과 동일).
                guard let flat = cleanedRawContext.createCGImage(
                    working, from: working.extent, format: .RGBA16, colorSpace: linearColorSpace)
                else { return nil }
                return (flat, computed, nil)
            }
            guard !Task.isCancelled,
                  let sourceAfter = try? AppModel.defectSourceIdentity(for: rawURL) else {
                await self.finishFailedCleanedRawBuild(
                    frame,
                    revision: revision,
                    quiet: quiet
                )
                return
            }
            guard sourceAfter == sourceIdentity else {
                await self.recoverFromChangedDefectSource(
                    frame,
                    revision: revision,
                    expectedRecipeIdentity: recipeSnapshot.identity,
                    quiet: quiet
                )
                return
            }
            guard !Task.isCancelled, let built else {
                await self.finishFailedCleanedRawBuild(
                    frame,
                    revision: revision,
                    quiet: quiet
                )
                return
            }
            let committed: Bool = await MainActor.run {
                guard self.ownsFrame(frame),
                      frame.cleanRawRevision == revision,
                      frame.defectRecipeIdentity == recipeSnapshot.identity else {
                    return false
                }
                self.installDefectRecipeIdentity(boundSnapshot.identity, on: frame)
                frame.cleanedRawImage = built.cleaned
                frame.cleanedRawMemoryIdentity = boundSnapshot.identity
                frame.cleanedRawEditCount = totalEditCount
                frame.cleanedRawAppliedStamps = appliedStamps
                if let canvas = built.canvas { frame.cleanedRawCanvas = canvas }
                self.invalidateDefectDependentDevelopCaches(frame)
                // 반복 큰 ROI에서 RGBA16 패치가 레이어/undo마다 누적되지 않게 최신 레이어만 캐시한다.
                frame.retainOnlyDefectPatchCache(for: cachedPatchEditID)
                for (id, patches) in built.patches {
                    if let idx = frame.defectEdits.firstIndex(where: { $0.id == id }) {
                        frame.defectEdits[idx].cachedPatches = patches
                    }
                }
                return true
            }
            // 픽셀이 준비된 시점까지가 재빌드 비용이다 — 뒤따르는 현상/저장은 이 구간에 넣지 않는다.
            trace.finish()
            guard committed else {
                await self.finishFailedCleanedRawBuild(frame, revision: revision, quiet: quiet)
                return
            }
            // 결함 제거가 "화면에 보이는" 시점 — 새 cleaned raw 를 소비한 첫(인터랙티브) 렌더
            // 발행(displayedCleanRawRevision) — 에 스피너/세션/persist/critical trim 을 먼저
            // 처리한다. 예전에는 0.14s 정착 대기 + 풀해상도 정착 렌더가 끝날 때까지 스피너가
            // 돌았다(제거는 인터랙티브 패스에서 이미 보이는데도). develop 이 스킵/실패로 끝나면
            // 완료 플래그가 대기를 푼다. 빌드 태스크 자체는 develop 완료까지 유지한다 —
            // cleanRawTask 를 develop 완료 신호로 쓰는 종료/테스트 시퀀스와, 정착 렌더가 소유
            // 정리 전에 끝나는 기존 수명을 보존한다.
            let developFinished = MainActorCompletionFlag()
            let developTask = Task { @MainActor [weak self, weak frame] in
                defer { developFinished.value = true }
                guard let self, let frame else { return }
                await self.developFrame(frame)
            }
            while await MainActor.run(body: {
                self.ownsFrame(frame)
                    && frame.cleanRawRevision == revision
                    && frame.displayedCleanRawRevision < revision
                    && !developFinished.value
            }) {
                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: 10_000_000)
            }
            await MainActor.run {
                guard self.ownsFrame(frame), frame.cleanRawRevision == revision else { return }
                // persist가 최신 CGImage를 먼저 캡처하고, 그 뒤 resident 정책이 메모리 압박에 따라
                // 축출한다. develop보다 먼저 축출하면 requiresCleanedRaw 렌더가 입력을 잃는다.
                if persist {
                    self.scheduleCleanedRawPersist(
                        frame,
                        image: built.cleaned,
                        identity: boundSnapshot.identity,
                        revision: revision
                    )
                }
                self.cleanedRawResidentInsert(frame)
                if frame.defectIsRemoving { self.clearRegionDefectSession(frame) }
                if !quiet {
                    frame.isRemovingDefects = false
                    if self.statusMessage == self.text(AppLocalizedPhrase.removingDefectsStatus) { self.statusMessage = "" }
                }
            }
            // 정착(풀해상도) 렌더까지 끝나면 빌드를 닫는다 — 디스크 백킹(TIFF) 저장은 분리된
            // 코얼레싱 태스크라 다음 편집이 인코딩을 기다리며 전체 재빌드로 강등되지 않는다.
            await developTask.value
            await MainActor.run {
                guard self.ownsFrame(frame), frame.cleanRawRevision == revision else { return }
                frame.cleanRawTask = nil
            }
        }
        frame.cleanRawTask = task
    }

    /// 커밋된 cleaned raw의 재생성 가능한 cache TIFF(축출 백킹 + 종료 시 굽기 소스)를 코얼레싱해
    /// 저장한다. 연속 편집 버스트 동안 이전 인코딩 예약을 취소하고 마지막 상태만 기록한다.
    /// 원본 raw와 제3자 XMP는 절대 수정하지 않는다. 저장 전후 currency 확인이 실패하면 조용히
    /// 버린다 — 백킹은 없어도 원본+기록으로 재빌드된다.
    func scheduleCleanedRawPersist(
        _ frame: ScanFrame,
        image: CGImage,
        identity: DefectRecipeIdentity,
        revision: Int
    ) {
        frame.cleanedRawPersistTask?.cancel()
        let frameID = frame.id
        let cleanedRawDirectory = diskStorage.cleanedRawURL
        frame.cleanedRawPersistTask = Task.detached(priority: .utility) { [weak self, weak frame] in
            try? await Task.sleep(nanoseconds: AppModel.cleanedRawPersistCoalesceNanoseconds)
            guard let self, let frame, !Task.isCancelled else { return }
            guard await self.cleanedRawBuildIsCurrent(
                frame,
                revision: revision,
                recipeIdentity: identity
            ) else { return }
            let newURL = CleanedRawCacheFile.makeBuildURL(
                frameID: frameID,
                in: cleanedRawDirectory
            )
            guard ImageLoader.saveScannerTIFF(image, to: newURL) else {
                try? FileManager.default.removeItem(at: newURL)
                return
            }
            await MainActor.run {
                guard self.ownsFrame(frame),
                      frame.cleanRawRevision == revision,
                      frame.defectRecipeIdentity == identity else {
                    try? FileManager.default.removeItem(at: newURL)
                    return
                }
                let previous = frame.cleanedRawDiskURL
                frame.cleanedRawDiskURL = newURL
                frame.cleanedRawDiskIdentity = identity
                if let previous,
                   previous != newURL,
                   CleanedRawCacheFile.isOwnedCacheURL(previous, frameID: frameID) {
                    try? FileManager.default.removeItem(at: previous)
                }
                frame.cleanedRawPersistTask = nil
                self.scheduleLibrarySave()
            }
        }
    }

    static let cleanedRawPersistCoalesceNanoseconds: UInt64 = 1_200_000_000

    /// cleaned raw 또는 증분 패치를 쓰기 직전에 현재 원본 바이트가 recipe에 묶인 원본과
    /// 같은지 백그라운드에서 확인한다. 원본이 같은 경로에서 바뀌었으면 이전 픽셀/패치/receipt를
    /// 모두 폐기하고 recipe를 unbound로 올린 뒤 새 원본에서만 전체 재빌드한다.

}

/// 백그라운드 태스크가 MainActor 작업의 완료 여부를 폴링하기 위한 단순 플래그.
@MainActor
final class MainActorCompletionFlag {
    var value = false
    nonisolated init() {}
}
