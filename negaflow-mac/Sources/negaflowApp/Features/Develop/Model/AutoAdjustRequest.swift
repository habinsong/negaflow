import Foundation

/// 자동 보정을 시작할 때의 입력 세대입니다. 값을 되돌려도 이전 요청은 살아나지 않습니다.
@MainActor
struct AutoAdjustRequest {
    private let revision: UInt64
    private let sourceRevision: UInt64
    private let rawRevision: Int

    init(_ frame: ScanFrame) {
        frame.autoAdjustRevision &+= 1
        revision = frame.autoAdjustRevision
        sourceRevision = frame.sourceLocationRevision
        rawRevision = frame.cleanRawRevision
    }

    func isCurrent(_ frame: ScanFrame) -> Bool {
        !Task.isCancelled && frame.autoAdjustRevision == revision
            && frame.inputGammaPreviewOverride == nil
            && frame.sourceLocationRevision == sourceRevision && frame.cleanRawRevision == rawRevision
    }
}
