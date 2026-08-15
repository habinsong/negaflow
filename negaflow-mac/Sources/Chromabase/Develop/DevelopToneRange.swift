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

    /// 흰색 계열 / 검정 계열. 끝점(백점·흑점) 제어라 ±1 로는 밀리지 않는 장면이 있어 ±2 로 둔다.
    ///
    /// 커널 계수(basicTone 의 whites 0.12 / blacks 0.06)와 마스크는 바꾸지 않는다 — ±1 구간의
    /// 결과는 이전과 완전히 동일하고, 넓어진 구간만 같은 기울기로 이어진다. 최종 clamp(0,1)이
    /// 끝점을 넘기지 않으므로 확장 구간에서도 값이 발산하지 않는다.
    ///
    /// 자동 톤(AutoAdjust.autoTone)은 whites 를 -1...1, blacks 를 -1...0.15 로 스스로 제한한다.
    /// 그 값은 이 범위 안에 그대로 들어오므로 자동 톤/자동 화이트밸런스/자동 색상과 어긋나지 않는다.
    public static let whites: ClosedRange<Double> = -2...2
    public static let blacks: ClosedRange<Double> = -2...2
}
