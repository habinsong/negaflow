import SwiftUI
import CoreGraphics
import Chromabase

extension AppModel {
    /// 복제 도장 스트로크(표시 정규좌표)를 base 좌표로 변환해 레이어로 누적한다.
    /// - existingOffset: 정렬 오프셋(base 정규). nil 이면 이 스트로크의 시작점과 소스로 확정한다.
    /// - Returns: 이번 스트로크에 실제 사용된 오프셋 — 호출측이 이후 스트로크에 그대로 쓴다(정렬 유지).
    @discardableResult
    func applyCloneStampStroke(displayUnits: [CGPoint], sourceBase: CGPoint,
                               existingOffset: CGVector?, diameterPx: CGFloat,
                               hardness: CGFloat, to frame: ScanFrame) -> CGVector? {
        guard !displayUnits.isEmpty, diameterPx > 0 else { return existingOffset }
        let baseSize = sourcePixelSize(for: frame)
        let transform = frame.imageTransform
        let basePoints = displayUnits.map { transform.displayUnitToBase($0, baseSize: baseSize) }
        let offset = existingOffset ?? CGVector(dx: sourceBase.x - basePoints[0].x,
                                                dy: sourceBase.y - basePoints[0].y)
        let stroke = CloneStampStroke(points: basePoints, offset: offset,
                                      diameter: diameterPx, hardness: min(max(hardness, 0), 1))
        let item = DefectEditItem(edit: .clone([stroke]),
                                  title: text(AppLocalizedPhrase.cloneStampEditTitleFormat, Int(diameterPx)),
                                  summary: text(AppLocalizedPhrase.cloneStampEditSummary),
                                  preview: [], baseSize: baseSize)
        guard appendDefectEdit(item, to: frame) else { return existingOffset }
        return offset
    }
}
