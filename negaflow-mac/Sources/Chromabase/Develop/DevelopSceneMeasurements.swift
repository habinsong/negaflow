import Foundation

/// 현상 파이프라인이 장면에서 읽어내는 측정값 묶음.
///
/// 이 값들은 **입력 raw·필름 베이스·필름 종류**에만 의존한다. 노출·대비·색 같은 인스펙터
/// 값이 걸리기 전 단계에서 재기 때문이다. 그런데도 예전에는 슬라이더를 한 칸 움직일 때마다
/// 전부 다시 쟀고, 그 재측정(축소 렌더 + CPU 정렬)이 프리뷰 한 장 값의 3분의 2를 먹었다
/// (2816px 프리뷰 실측: 한 틱 39.5 ms 중 25.5 ms).
///
/// 그래서 호출부가 이 묶음을 들고 있다가 다음 현상에 되돌려준다. 값이 채워져 있으면 그대로
/// 쓰고, 비어 있으면 재서 채운다. 입력 raw 나 베이스가 바뀌면 호출부가 통째로 버린다.
public struct DevelopSceneMeasurements: Sendable, Equatable {
    /// 네거티브 반전이 쓰는 채널별 밀도 범위. auto 경로는 sampleStats, 프리셋 경로는
    /// presetStats 결과가 들어간다 — 둘 다 장면 실측에 기대므로 같은 슬롯을 쓴다.
    /// 베이스 추정 모드가 바뀌면 호출부가 묶음째 버린다.
    var inversionStats: NegativeInversion.ChannelStats?
    /// 뮤트한 장면 채도 보정량(sceneMeanSaturation 에서 유도).
    var mutedVibranceAmount: Double?
    /// 스캐너 타겟 그레이드의 장면 톤 앵커(sceneToneAnchor).
    var scannerSceneAnchor: ScannerTargetGrade.SceneToneAnchor?
    /// 자동 레벨이 검출한 채널별 끝점.
    var autoLevelsPoints: AutoLevels.Points?
    /// 자동 중립화가 쓰는 장면 median.
    var neutralBalanceMedian: SIMD3<Double>?
    /// EXPIRED 복구가 쓰는 중립축 증거.
    var rescueRecovery: RescueGrade.Recovery?

    public init() {}
}
