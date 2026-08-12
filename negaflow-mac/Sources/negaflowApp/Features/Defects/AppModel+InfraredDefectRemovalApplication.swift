import Chromabase
import SwiftUI

extension AppModel {
    func applyInfraredDetection(
        _ outcome: Result<InfraredDefectRemoval.Detection, InfraredDefectRemoval.Failure>,
        to frame: ScanFrame
    ) {
        switch outcome {
        case .failure(.noDefects):
            statusMessage = text(AppLocalizedPhrase.infraredCleanNoDefectsStatus)
            developAfterInfraredProducedNothing(frame)
        case .failure(.coverageTooHigh):
            statusMessage = text(AppLocalizedPhrase.infraredCleanCoverageAbortStatus)
            developAfterInfraredProducedNothing(frame)
        case .failure(.alignmentUnreliable):
            statusMessage = infraredText(.alignmentUnreliable)
            developAfterInfraredProducedNothing(frame)
        case .failure(.cancelled):
            rearmInfraredAutoClean(frame)
            developAfterInfraredProducedNothing(frame)
            return   // 사용자가 취소 — 상태 메시지 없음
        case .failure:
            // 읽기/정합 실패는 이 원본에 대해 확정된 결과다 — 표시를 유지해 그 사진을 볼 때마다
            // 같은 실패를 다시 돌리지 않는다(원본이 바뀌면 relink 경로가 표시를 되돌린다).
            statusMessage = text(AppLocalizedPhrase.infraredCleanFailedStatus)
            developAfterInfraredProducedNothing(frame)
        case .success(let detection):
            guard !detection.clusters.isEmpty, !detection.components.isEmpty else {
                statusMessage = text(AppLocalizedPhrase.infraredCleanNoDefectsStatus)
                developAfterInfraredProducedNothing(frame)
                return
            }
            let baseSize = CGSize(width: detection.width, height: detection.height)
            let breakdown = DefectClassBreakdown(components: detection.components)
            let preview = detection.components.map { component in
                DefectMaskPreviewComponent(
                    classification: component.classification,
                    confidence: component.confidence,
                    points: component.previewPoints.map {
                        CGPoint(x: $0.x / baseSize.width, y: $0.y / baseSize.height)
                    }
                )
            }
            let item = DefectEditItem(
                edit: .infrared(clusters: detection.clusters),
                label: .infrared(count: detection.components.count),
                summaryKind: .classBreakdown(breakdown),
                preview: preview,
                baseSize: baseSize
            )
            // 성공 경로의 현상은 cleaned raw 빌드가 끝나면서 발행된다. 레이어를 못 붙였으면
            // 아무도 현상을 걸지 않으므로 여기서 원본 그대로 현상한다.
            guard appendDefectEdit(item, to: frame) else {
                developAfterInfraredProducedNothing(frame)
                return
            }
            statusMessage = text(
                AppLocalizedPhrase.infraredCleanAppliedFormat,
                detection.components.count
            )
        }
    }
}

extension DefectEditItem {
    var isInfrared: Bool {
        if case .infrared = edit { return true }
        return false
    }
}
