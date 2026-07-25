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
// 필름 공정이 명확한 컬러 네거티브만 자동 적용한다. B&W와 종류가 확인되지 않은 슬라이드는
// IR 투과를 추정하지 않고 fail closed 한다.
extension AppModel {

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

        statusMessage = text(AppLocalizedPhrase.infraredCleanDetectingStatus)
        let trace = AppDiagnostics.start(.infraredDefect, category: .defects)
        let rawURL = frame.rawScanURL
        let frameLifecycleRevision = frame.defectDetectRevision
        let session = beginInfraredCleanSession(for: frame)
        let task = Task.detached(priority: .userInitiated) {
            let outcome: Result<InfraredDefectRemoval.Detection, InfraredDefectRemoval.Failure> = autoreleasepool {
                guard !Task.isCancelled else { return .failure(.unreadable) }
                guard let raw = ChromabaseEngine().loadScannerImage(rawURL),
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

    @discardableResult
    func beginInfraredCleanSession(for frame: ScanFrame) -> InfraredCleanSessionToken {
        InfraredCleanSessionRegistry.begin(owner: self, frameID: frame.id)
    }

    func cancelInfraredClean(_ frame: ScanFrame) {
        InfraredCleanSessionRegistry.cancel(owner: self, frameID: frame.id)
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
            return false
        }
        InfraredCleanSessionRegistry.finish(session)
        applyInfraredDetection(outcome, to: frame)
        return true
    }

}
