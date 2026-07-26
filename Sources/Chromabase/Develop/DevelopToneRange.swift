import Foundation

// 톤 조정의 허용 범위. 슬라이더·키보드·히스토그램 드래그가 같은 값을 봐야 한다 — 예전에는 세 곳에
// 따로 하드코딩되어 있어 한 곳만 고치면 조작 경로마다 상한이 달라졌다.
public enum DevelopToneRange {
    /// 노출(스톱). 슬라이드 필름의 노출 부족 복구는 3스톱을 넘기는 경우가 있어 Lightroom·
    /// Capture One 과 같은 ±5 로 둔다. 키보드 nudge 는 절대 폭(0.01/0.10)이고 값은 직접 입력할 수도
    /// 있으므로, 범위를 넓혀도 미세 조정 정밀도는 그대로다.
    ///
    /// 자동 톤(AutoAdjust.autoTone)이 내는 노출은 자체적으로 -1.2...1.5 로 제한되어 이 범위 안에
    /// 들어온다 — 범위를 넓혀도 자동 조정과 어긋나지 않는다.
    public static let exposure: ClosedRange<Double> = -5...5
}
