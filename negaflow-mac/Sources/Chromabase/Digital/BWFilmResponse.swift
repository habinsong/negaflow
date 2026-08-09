import Foundation

// MARK: - BWFilmResponse (유제 파라미터 → 곡선 계수)
//
// 필름별로 곡선을 손으로 그려 넣지 않는다. 데이터시트에서 온 물리량(콘트라스트 인덱스,
// 토우/숄더 형태, 관용도, Dmax)에서 곡선을 **유도**한다. 그래야 필름을 추가할 때 곡선을
// 다시 튜닝할 필요가 없고, 어떤 컷에서도 같은 규칙이 돌아간다.
//
// 여기 있는 계수들은 필름 하나를 보기 좋게 만드는 값이 아니라, 물리량 축을 렌더 축으로
// 옮기는 환산비다. 값을 바꾸면 15 종 전부가 함께 움직인다 — 그것이 의도다.
struct BWFilmResponse {

    /// 사람 눈의 휘도 가중치. 유제 특성을 0 으로 두었을 때 돌아갈 중립 기준선이다.
    static let neutralWeights = SIMD3<Double>(0.2126, 0.7152, 0.0722)

    /// 일반 촬영용 흑백 네거티브가 표준 현상에서 수렴하는 콘트라스트 인덱스.
    /// 인화지 grade 2 가 이 기울기를 정상으로 렌더하도록 설계되었으므로, 이 값이 "대비 0" 이다.
    static let referenceContrastIndex = 0.55

    /// 관용도 기준선(스톱). 이보다 넓으면 명부를 눕혀 담고, 좁으면 명부가 빨리 붙는다.
    static let referenceLatitude = 9.0

    /// 토우/숄더 형태의 기준선(0.5 = 중립).
    static let referenceCurveShape = 0.50

    var weights: SIMD3<Double>
    var contrast: Double
    var toe: Double
    var shoulder: Double
    var deepen: Double
    var black: Double
    var white: Double

    init(profile: BWFilmProfile, intensity: Double) {
        let k = min(max(intensity, 0), 1)

        // 분광 가중치는 중립 휘도에서 유제 가중치로 옮겨 간다. 강도 0 이면 이 스테이지가
        // 없을 때와 똑같은 중립 그레이가 나와야 한다 — 그것이 강도의 정의다.
        weights = Self.neutralWeights + (profile.spectralWeights - Self.neutralWeights) * k

        // 대비: 반전은 뒤에서 대비를 되살려 줄 인화지가 없어 유제 대비가 곧 최종 대비다.
        // 그래서 같은 편차라도 반전 쪽 환산비가 크다.
        let contrastGain = profile.isReversal ? 1.4 : 1.1
        contrast = (profile.contrastIndex - Self.referenceContrastIndex) * contrastGain

        // 토우: 긴 토우(전통 큐빅)는 암부를 들어 올리고, 곧은 토우(T-GRAIN/Core-Shell)는
        // 암부를 더 떨군다. 암부에만 실리도록 커널이 (1−y)³ 로 가중한다.
        toe = (profile.toeSoftness - Self.referenceCurveShape) * 0.10

        // 숄더: 부드러운 숄더와 넓은 관용도는 둘 다 명부를 눕혀 담는 쪽으로 작용하고,
        // 급한 숄더와 좁은 관용도는 명부를 빨리 붙인다. 같은 방향의 두 축이므로 한 항으로 합친다.
        let shape = (profile.shoulderSoftness - Self.referenceCurveShape) * 0.09
        let latitude = (profile.latitudeStops - Self.referenceLatitude) / Self.referenceLatitude * 0.05
        shoulder = -(shape + latitude)

        // 반전의 깊은 검정. 중간톤을 함께 어둡게 만들면 노출이 달라 보이므로 암부에만 싣는다.
        deepen = profile.isReversal ? (profile.dmaxMultiplier - 1.0) * 0.10 : 0

        // 매체의 흑·백 한계. 인화지는 순흑에 붙지 않고(그 바닥이 필름 인화의 검정이다),
        // 반전은 필름 자체가 최종물이라 바닥까지 간다.
        black = profile.isReversal ? 0.0 : 0.008
        white = profile.isReversal ? 1.0 : 0.994
    }
}
