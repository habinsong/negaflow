import Foundation
import Chromabase

extension AppModel {
    /// 중립 스포이드: 찍은 점이 무채색이 되도록 색온도·틴트를 대입한다(되돌리기 한 단계).
    /// 값은 화이트밸런스 입력에서 재므로 현재 온도·틴트와 무관하게 같은 점은 같은 결과가 된다.
    func pickNeutralWhiteBalance(at baseUnit: CGPoint, frame: ScanFrame) {
        guard ownsFrame(frame) else { return }
        let point = CGPoint(x: min(max(baseUnit.x, 0), 1), y: min(max(baseUnit.y, 0), 1))
        Task { [weak self] in
            guard let self,
                  await self.prepareCleanedRawForConsumption(frame),
                  self.ownsFrame(frame) else { return }
            let expectedDefectIdentity = frame.boundDefectRecipeIdentity
            let cleanRawRevision = frame.cleanRawRevision
            let sourceRevision = frame.sourceLocationRevision
            let filmType = frame.filmType
            let baseKey = FilmBaseCacheKey(
                filmType: frame.filmType,
                mode: frame.params.baseEstimationMode,
                manualBaseRGB: frame.params.manualBaseRGB,
                filmStockDminID: frame.params.filmStockDminID,
                lightSourceProfileID: frame.params.lightSourceProfileID,
                imageTransform: frame.imageTransform
            )
            let snapshot = self.makeSnapshot(
                for: frame,
                baseKey: baseKey,
                needsRawPreview: false,
                needsNeutralPreview: false,
                needsDebugPreviews: false,
                needsThumbnail: false,
                proxyMaxDimension: DevelopFrameRenderer.fullMaxDimension
            )
            let sampled = await Task.detached(priority: .userInitiated) { () -> SIMD3<Double>? in
                (try? DevelopFrameRenderer.whiteBalanceInputSample(snapshot, atBaseUnit: point)) ?? nil
            }.value
            guard self.ownsFrame(frame),
                  frame.cleanRawRevision == cleanRawRevision,
                  frame.sourceLocationRevision == sourceRevision,
                  frame.filmType == filmType,
                  frame.boundDefectRecipeIdentity == expectedDefectIdentity else { return }
            guard let sampled, let wb = NeutralWhiteBalancePicker.solve(sampled) else {
                self.statusMessage = self.text(AppLocalizedPhrase.neutralPickFailed)
                return
            }
            let user = Self.userWhiteBalance(solved: wb, preset: frame.preset)
            self.applyTransferredSettings(to: [frame]) {
                $0.params.warmth = user.warmth
                $0.params.tint = user.tint
            }
            self.statusMessage = self.text(AppLocalizedPhrase.neutralPickedFormat, user.warmth, user.tint)
            Task { await self.developFrame(frame) }
        }
    }

    /// 룩 프리셋의 온도·틴트에 사용자 값이 더해진다(DevelopParameters(preset:overrides:)) — 합이
    /// 풀어낸 값이 되도록 프리셋 몫을 빼고 슬라이더 범위로 자른다.
    nonisolated static func userWhiteBalance(
        solved: (warmth: Double, tint: Double),
        preset: LookPreset?
    ) -> (warmth: Double, tint: Double) {
        let presetParams = preset?.baseParameters
        let limit = WhiteBalanceGains.maximum
        return (min(max(solved.warmth - (presetParams?.warmth ?? 0), -limit), limit),
                min(max(solved.tint - (presetParams?.tint ?? 0), -limit), limit))
    }
}
