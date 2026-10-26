import Foundation

/// 현상 파이프라인이 장면에서 읽어내는 측정값 묶음.
///
/// 입력 raw·필름 베이스·필름 종류와 반전 방식에 의존한다. 노출·대비·색 보정 전 단계에서
/// 측정하므로 그 조정에는 재사용할 수 있다. 그런데도 예전에는 슬라이더를 한 칸 움직일 때마다
/// 전부 다시 쟀고, 그 재측정(축소 렌더 + CPU 정렬)이 프리뷰 한 장 값의 3분의 2를 먹었다
/// (2816px 프리뷰 실측: 한 틱 39.5 ms 중 25.5 ms).
///
/// 그래서 호출부가 이 묶음을 들고 있다가 다음 현상에 되돌려준다. 값이 채워져 있으면 그대로
/// 쓰고, 비어 있으면 재서 채운다. 입력·베이스·반전 방식이 바뀌면 호출부가 통째로 버린다.
public struct DevelopSceneMeasurements: Sendable, Equatable {
    /// 장면을 잴 영역(크롭한 사진 영역, 변형 전 원본 좌표). nil 이면 프레임 전체(기존 6% 인셋).
    /// 측정값의 입력이므로 영역이 바뀌면 호출부가 묶음째 버린다.
    public var analysisRegion: AnalysisRegion?
    public internal(set) var cameraToWorking: CameraToWorkingMatrix?
    var inputGammaReferenceRange: SIMD3<Double>?
    /// 자동 밸런스 ON과 스캐너 타깃은 장면 범위를, OFF는 고정 범위를 저장한다.
    /// 베이스·반전 타깃·스캐너 프로파일이 바뀌면 호출부가 묶음째 버린다.
    var inversionStats: NegativeInversion.ChannelStats?
    /// 뮤트한 장면 채도 보정량(sceneMeanSaturation 에서 유도).
    var mutedVibranceAmount: Double?
    /// 스캐너 타겟 그레이드의 장면 톤 앵커(sceneToneAnchor).
    var scannerSceneAnchor: ScannerTargetGrade.SceneToneAnchor?
    /// 자동 레벨이 검출한 채널별 끝점.
    var autoLevelsPoints: AutoLevels.Points?
    /// 자동 색상이 장면 중립축에 맞춘 보정(근거가 없으면 항등).
    var neutralBalanceCorrection: NeutralBalance.Correction?
    /// EXPIRED 복구가 쓰는 중립축 증거.
    var rescueRecovery: RescueGrade.Recovery?

    public init() {}
}
