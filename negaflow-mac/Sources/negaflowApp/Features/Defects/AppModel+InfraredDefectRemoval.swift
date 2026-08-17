import Chromabase
import CoreImage

// 하드웨어 IR(적외선) 채널 기반 자동 결함 제거.
//
// 스캔 시 IR 토글이 켜져 있으면 플러그인이 본 스캔과 같은 해상도/영역의 IR 채널 TIFF 를
// 함께 산출한다(ScanResult.infraredFileURL → ScanFrame.infraredScanURL). 스캔 직후 이
// 경로가 자동 실행되어: IR 검출(InfraredDefectRemoval) → Defect Layer 한 장(.infrared) 로 누적 →
// 통합 빌드(appendDefectEdit)가 cleaned raw 를 갱신하고 재현상한다. 사용자는 결함이
// 제거된 사진을 보게 되고, 레이어 켜기/끄기·강도·삭제·⌘Z 로 언제든 되돌릴 수 있다.
//
// 화상이 색소인 컬러 필름(네거티브·슬라이드)에만 자동 적용한다. 흑백은 화상이 은입자라
// 적외선을 막으므로 fail closed 한다([InfraredFilmCompatibility]).
extension AppModel {

    /// IR 쌍이 있는 프레임을 선택했을 때의 자동 실행. GrainMend IR 기록은 세션 메모리에만
    /// 살고 종료 시 폐기되므로(굽지 않는다 — IR 파일에서 언제든 다시 만들 수 있다), 앱을 다시
    /// 켜고 그 프레임을 선택하면 여기서 되살린다. 한 세션에 프레임당 한 번만 시도한다 —
    /// 결과가 "결함 없음"이면 레이어가 안 생겨서 선택할 때마다 다시 돌게 된다.
    /// 선택이 이 프레임에 **머무를 때만** 자동 복원을 시작한다. 화살표로 훑고 지나가는 프레임
    /// 마다 원본(수십 MB TIFF)을 통째로 디코드해 검출을 돌리면 메모리와 CPU 가 금방 바닥난다.
    func scheduleInfraredCleanForSelection(_ frame: ScanFrame) {
        guard !frame.infraredAutoCleanAttempted, frame.infraredScanURL != nil else { return }
        let frameID = frame.id
        Task { [weak self, weak frame] in
            try? await Task.sleep(nanoseconds: AppModel.infraredSelectionDebounceNanoseconds)
            guard let self, let frame, self.selectedFrameID == frameID else { return }
            self.runInfraredCleanIfNeeded(frame)
        }
    }

    static let infraredSelectionDebounceNanoseconds: UInt64 = 400_000_000

    func runInfraredCleanIfNeeded(_ frame: ScanFrame) {
        guard !frame.infraredAutoCleanAttempted,
              frame.infraredScanURL != nil,
              frame.isSourceAvailable,
              !frame.isPreviewScan,
              !frame.defectEdits.contains(where: { $0.isInfrared }),
              InfraredFilmCompatibility(filmType: frame.filmType).allowsAutomaticCorrection
        else { return }
        runInfraredClean(frame)
    }

    /// 스캔 직후(또는 수동으로) IR 채널 결함 제거를 실행한다. 결과는 Defect Layer 로 쌓인다.
    func runInfraredClean(_ frame: ScanFrame) {
        guard let irURL = frame.infraredScanURL else { return }
        guard frames.contains(where: { $0 === frame }) else { return }
        guard InfraredFilmCompatibility(filmType: frame.filmType).allowsAutomaticCorrection else {
            statusMessage = infraredText(.unverifiedFilm)
            return
        }
        // 이미 IR 레이어가 있으면 중복 적용하지 않는다(삭제 후 재실행은 가능).
        guard !frame.defectEdits.contains(where: { $0.isInfrared }) else { return }

        frame.infraredAutoCleanAttempted = true
        statusMessage = text(AppLocalizedPhrase.infraredCleanDetectingStatus)
        let trace = AppDiagnostics.start(.infraredDefect, category: .defects)
        let rawURL = frame.rawScanURL
        let sourceKind = frame.sourceKind
        // 검출은 cleaned raw 빌드와 **같은 픽셀**을 봐야 한다 — 로더가 다르면 방향(EXIF)과
        // 색 해석이 갈려 마스크가 엉뚱한 자리에 얹힌다.
        let rawRendering = ImageLoader.RAWRendering
            .forDigitalSource(frame.params.isDigitalSource)
        let frameLifecycleRevision = frame.defectDetectRevision
        let session = beginInfraredCleanSession(for: frame)
        let task = Task.detached(priority: .userInitiated) {
            let outcome: Result<InfraredDefectRemoval.Detection, InfraredDefectRemoval.Failure> = autoreleasepool {
                guard !Task.isCancelled else { return .failure(.unreadable) }
                let engine = ChromabaseEngine()
                let rawImage = sourceKind == .importedFile
                    ? engine.loadImportedImage(rawURL, rawRendering: rawRendering)
                    : engine.loadScannerImage(rawURL)
                guard let raw = rawImage,
                      let infrared = ImageLoader.loadScannerTIFF(irURL) else {
                    return .failure(.unreadable)
                }
                // 단계 경계 취소 훅 — 55MP 검출 중에도 수 초가 아니라 즉시 취소에 반응한다.
                return InfraredDefectRemoval.detect(raw: raw, infrared: infrared,
                                          isCancelled: { Task.isCancelled })
            }
            switch outcome {
            case .success, .failure(.noDefects), .failure(.cancelled):
                trace.finish()
            case .failure(.unreadable):
                trace.fail(code: "infrared_unreadable")
            case .failure(.tooSmall):
                trace.fail(code: "infrared_too_small")
            case .failure(.alignmentUnreliable):
                trace.fail(code: "infrared_alignment_unreliable")
            case .failure(.coverageTooHigh):
                trace.fail(code: "infrared_coverage_too_high")
            }
            _ = await MainActor.run {
                self.completeInfraredClean(
                    outcome,
                    to: frame,
                    session: session,
                    frameLifecycleRevision: frameLifecycleRevision,
                    taskWasCancelled: Task.isCancelled
                )
            }
        }
        InfraredCleanSessionRegistry.install(task, for: session)
    }

    /// 스캔 직후 경로: IR 쌍이 있으면 **정착 현상을 한 번만** 돌린다.
    ///
    /// 예전에는 원본으로 정착 현상을 돌리는 동안 IR 보정이 끝나 cleaned raw 가 생기고, 그
    /// 결과로 같은 프레임을 풀해상도로 한 번 더 현상했다. 마지막으로 스캔한 컷(=선택된 컷)은
    /// 이 두 패스가 겹쳐 유독 느렸고, 그 사이 원본 렌더가 cleaned raw 를 기다리다 "이미지 로드
    /// 실패"로 끝나기도 했다. 썸네일 시드만 먼저 띄우고, 정착 현상은 IR 결과가 정해진 뒤에 돈다.
    func developAfterScan(_ frame: ScanFrame) {
        // 스캔 직후 프레임을 선택하면서 이미 걸렸을 수 있다 — 그때는 다시 걸지 않고 결과를
        // 기다린다. 시도 표시가 곧 "IR 경로가 정착 현상을 책임진다"는 뜻이다.
        runInfraredCleanIfNeeded(frame)
        guard frame.infraredAutoCleanAttempted else {
            Task { await developFrameAfterFastPreview(frame) }
            return
        }
        Task { [weak self, weak frame] in
            guard let self, let frame else { return }
            if let seed = frame.initialThumbnailSeedTask { await seed.value }
            await self.seedFastPreview(frame)
        }
    }

    /// IR 보정이 레이어를 남기지 못했을 때(결함 없음·실패·취소) 원본 그대로 정착 현상한다.
    /// 성공 경로는 cleaned raw 빌드가 끝나면서 현상을 발행하므로 여기서 돌리지 않는다.
    func developAfterInfraredProducedNothing(_ frame: ScanFrame) {
        Task { await developFrameAfterFastPreview(frame) }
    }

    @discardableResult
    func beginInfraredCleanSession(for frame: ScanFrame) -> InfraredCleanSessionToken {
        InfraredCleanSessionRegistry.begin(owner: self, frameID: frame.id)
    }

    func cancelInfraredClean(_ frame: ScanFrame) {
        InfraredCleanSessionRegistry.cancel(owner: self, frameID: frame.id)
    }

    /// 사용자가 GrainMend 수동 도구(자동/가이드)를 시작할 때 IR 자동 정리에 길을 내준다.
    ///
    /// IR 검출은 실기 2400dpi 한 컷에서 26~52초가 걸리는 백그라운드 작업이다(실측). 그동안
    /// 수동 검출이 시작되면 둘이 서로의 revision 을 밀어 **양쪽 다 조용히 사라졌다**:
    /// 수동 검출이 defectDetectRevision 을 올려 IR 결과가 버려지고, 반대로 IR 이 레이어를
    /// 붙이며 cleanRawRevision 을 올려 진행 중이던 수동 검출 세션이 통째로 폐기됐다.
    /// 사용자의 명시적 조작이 이긴다 — IR 은 취소하되 **다시 시도할 수 있게** 표시를 푼다.
    func yieldInfraredCleanToManualTool(_ frame: ScanFrame) {
        guard InfraredCleanSessionRegistry.isRunning(owner: self, frameID: frame.id) else { return }
        cancelInfraredClean(frame)
        rearmInfraredAutoClean(frame)
    }

    /// 이번 실행은 못 썼지만 원인이 일시적일 때(취소·경합·읽기 실패) 다음 선택에서 다시
    /// 만들 수 있게 시도 표시를 푼다. "결함 없음"처럼 결과가 확정된 경우는 풀지 않는다 —
    /// 표시가 없으면 그 사진을 볼 때마다 55MP 검출이 다시 돌아간다.
    func rearmInfraredAutoClean(_ frame: ScanFrame) {
        guard !frame.defectEdits.contains(where: { $0.isInfrared }) else { return }
        frame.infraredAutoCleanAttempted = false
    }

    /// 비동기 검출 결과가 여전히 같은 프레임의 최신 실행인지 확인한 뒤에만 상태/레이어를 갱신한다.
    /// 프레임 삭제는 목록 소유권과 lifecycle revision으로, 재실행/취소는 session token으로 막는다.
    @discardableResult
    func completeInfraredClean(
        _ outcome: Result<InfraredDefectRemoval.Detection, InfraredDefectRemoval.Failure>,
        to frame: ScanFrame,
        session: InfraredCleanSessionToken,
        frameLifecycleRevision: Int,
        taskWasCancelled: Bool
    ) -> Bool {
        guard !taskWasCancelled,
              InfraredCleanSessionRegistry.isCurrent(session),
              frame.defectDetectRevision == frameLifecycleRevision,
              frames.contains(where: { $0 === frame }),
              !frame.defectEdits.contains(where: { $0.isInfrared }) else {
            InfraredCleanSessionRegistry.finish(session)
            // 결과를 버리는 이유는 전부 일시적이다(취소·경합·프레임 교체). 표시를 풀지 않으면
            // 이 세션에서는 IR 먼지 제거를 다시 만들 방법이 없어진다.
            if frames.contains(where: { $0 === frame }) { rearmInfraredAutoClean(frame) }
            return false
        }
        InfraredCleanSessionRegistry.finish(session)
        applyInfraredDetection(outcome, to: frame)
        return true
    }

}
