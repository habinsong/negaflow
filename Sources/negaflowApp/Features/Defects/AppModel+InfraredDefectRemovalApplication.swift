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
        case .failure(.coverageTooHigh):
            statusMessage = text(AppLocalizedPhrase.infraredCleanCoverageAbortStatus)
        case .failure(.alignmentUnreliable):
            statusMessage = infraredText(.alignmentUnreliable)
        case .failure(.cancelled):
            return   // 사용자가 취소 — 상태 메시지 없음
        case .failure:
            statusMessage = text(AppLocalizedPhrase.infraredCleanFailedStatus)
        case .success(let detection):
            guard !detection.clusters.isEmpty, !detection.components.isEmpty else {
                statusMessage = text(AppLocalizedPhrase.infraredCleanNoDefectsStatus)
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
            appendDefectEdit(item, to: frame)
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
