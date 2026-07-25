import Foundation

// 후보 bool 맵 → 연결요소 형태 게이트 → RGBA8 마스크(흰색=결함).
// 먼지는 작은 blob, 스크래치는 길고 가는 선만 통과시킨다.
enum DefectComponentMask {
    /// 스크래치로 인정하는 평균 두께 상한(검출 해상도 px). 실제 스크래치 후보(ridge/thin top-hat)는
    /// 가늘다 — 이보다 두꺼운 "스크래치" 컴포넌트는 텍스처/디테일 카펫이 형태 게이트를 우회한 것이므로
    /// 기각한다(칠 면적 통째 와이프 방지 구조 가드). 더 두꺼운 진짜 결함은 두께 게이트(dust)가 맡는다.
    static let maxScratchThickness = 12.0

    /// weak-only(히스테리시스 코어 없는) 스크래치를 기하 증거만으로 채택하는 최소 길이/신장도/두께.
    /// LSD/a-contrario 정신: SNR floor 를 통과한 정렬 픽셀이 이 길이로 연결될 확률은 지수적으로
    /// 작다 — "매우 길고 매우 가는" 것만 그레인-안전하게 채택한다. 짧은 weak-only 는 그레인과
    /// 구분 불가라 기존대로 기각.
    static let weakGeoMinLength = 80.0
    static let weakGeoMaxThickness = 3.0
    static let weakGeoMinAspect = 15.0

    /// 먼지 고립(isolation) 게이트: 결함은 "주변과 크게 다른" 고립 사건이다(a-contrario 정신).
    /// 컴포넌트 bbox 둘레 링에 자기 이외의 "덩어리(chunky, ≥ minStruct px)" 먼지 후보가 이 비율보다
    /// 많으면 텍스처/디테일(잎·자갈·창문 격자 류)의 파편으로 보고 기각한다 — 촘촘한 정상 디테일이
    /// 컴팩트 게이트를 개별 통과해 칠/ROI 면적이 조각조각 재합성되는 와이프를 막는다.
    /// 그레인 후보(1~수 px)는 덩어리가 아니라 세지 않으므로 그레인 위 결함 제거는 유지된다.
    static let isolationMinStruct = 8
    static let isolationRingPadMax = 24
    static let isolationMaxRingDensity = 0.10

    /// 그레인 필드 필터: 작은(≤ smallMax px) 컴포넌트가 반경 radius(Chebyshev) 안에 자기 포함
    /// count 개 이상 빽빽하면 그레인 필드로 보고 그 작은 컴포넌트들을 전부 버린다. 고립된 작은
    /// 먼지·큰/긴 결함은 보존한다. 컴포넌트를 "제거만" 하므로(추가 없음) 검출을 악화시킬 수 없는
    /// 순수 안전 가드다 — 실제 필름 그레인(1px 크로마틱 고주파, 합성으로 재현 불가)은 aggressive
    /// 브러시 임계를 낱알 단위로 대량 통과해, 낱알 복원 수백 개가 dilate 와 청크 중첩으로 쌓이면
    /// 칠 자국을 따라 층층이 뿌옇게 밀리는 와이프가 된다(실전 보고). 판정은 진폭이 아닌 "빽빽한
    /// 작은 컴포넌트" 시그니처라 그레인 진폭과 무관하게 일반화된다.
    static let grainFieldSmallMax = 12
    // 부분 ROI도 필름 그레인 안전선을 유지한다. 확장 검출의 trusted 경로로 들어온 고대비 입자도
    // 1~2px 크기로 밀집하면 예외 없이 버리고, 3x3 이상 실제 먼지는 크기 범위 밖이라 보존한다.
    static let constrainedRegionGrainFieldSmallMax = 4
    static let grainFieldRadius = 48
    static let grainFieldCount = 10

    /// 구조물 선 텍스처 배제(전역 자동 전용 구조 가드) — a-contrario/텍스처 분류 정신.
    /// 스크래치는 "매끈한 배경 위 고립된 선"이지만 보도블럭·벽돌·창틀·블라인드는 "선이 빽빽한
    /// 텍스처 영역"이다(가로/세로/대각/곡선/방사형 무관). 방향 기반 평행 그룹핑은 곡선·방사형에서
    /// 국소 방향이 제각각이라 무너지므로, **방향 무관 국소 선-밀도**로 판별한다: 각 스크래치 선
    /// 컴포넌트 주변(반경)에 다른 선 컴포넌트가 임계 이상 빽빽하면 텍스처로 보고 버린다. 순수 제거라
    /// 검출을 악화시킬 수 없고 임계(검출)는 불변이다. 고립 스크래치·조각난 단일 스크래치(이웃 소수)는
    /// 보존된다.
    static let gridLineMinField = 8        // 이만큼 선이 있어야 "텍스처/구조 판정"을 시도
    static let gridLineMinLength = 6.0     // 세는 최소 주축 길이(dash 세그먼트 포함)
    // 메커니즘 A — 방향 무관 국소 밀도(보도블럭·벽돌 등 dash 텍스처). 중심점 반경 내 이웃 선 수.
    static let gridLineRadiusMin = 48
    static let gridLineRadiusDivisor = 6   // 밀도 반경 = max(min, min(w,h)/divisor)
    static let gridLineDenseCount = 5      // 반경 내 이웃 선 수(자신 포함) 이상이면 텍스처로 기각
    // 메커니즘 B — 방향 기반(성긴 긴 평행선/격자: 펜스·블라인드·창살). 확장 bbox 중첩으로 이웃 판정.
    static let gridLineOrientTol = 22.0    // 평행/직교 판정 각도 허용(도)
    static let gridLineStructRadiusDivisor = 4  // 구조선 반경(밀도보다 넓게)
    static let gridLineParallelField = 5   // 같은 방향 규칙 반복으로 보는 평행선 수(자신 포함)
    static let gridLineMinAlong = 2        // 격자: 자신 포함 평행선 수(≥1 동반)
    static let gridLineMinPerp = 2         // 격자: 직교선 수
    /// 같은 직선 위에 놓인 조각으로 보는 축 이탈 허용(px). 저대비 스크래치 하나가 여러 조각으로
    /// 끊기면 조각들은 서로 평행 + 같은 축 위에 있다 — 이 조각들을 "이웃 선"으로 세면 결함
    /// **하나**가 스스로를 구조 텍스처로 만들어 기각된다(자동에서만 스크래치 검출률이 떨어지던
    /// 원인). 구조물 선(벽돌·블라인드·격자)은 서로 평행해도 축이 어긋나 있으므로 여전히 세어진다.
    /// 값은 스크래치 두께 상한과 같다 — 그보다 멀리 벗어난 선은 같은 결함일 수 없다.
    static let gridLineCollinearOffset = maxScratchThickness
    /// 구조 텍스처 표는 "길이가 비슷한 선"끼리만 던진다. 벽돌줄눈·블라인드·격자는 규칙적이라 길이가
    /// 고르지만, 필름 스크래치는 주변 잔선보다 훨씬 길다 — 짧은 잔선 다발이 근처에 있다는 이유로 긴
    /// 스크래치가 구조로 몰려 기각되던 것이 자동 검출률 저하의 실제 원인이었다.
    static let gridLineComparableLengthRatio = 2.5

    /// 브러시 와이프 퓨즈(regionArea 가 주어진 브러시 경로 전용) — 결함은 희소 사건이라는
    /// 물리 사전을 절대 상한으로 강제한다. 검출 임계·SNR 은 불변(임계 상향은 실전 희미한 스크래치
    /// 제거를 죽였던 롤백 전력) — 채택 단계에서 상대 세기·총량만 제한하는 구조 가드다.
    ///  ① 스크래치: preferredAngle 방향 적분이 실제 필름 그레인(덩어리·상관 노이즈 — 백색 합성
    ///    그레인과 달리 적분 잔차 ~0.01이 남는다)을 스트로크 방향 "줄무늬" 컴포넌트로 이어 붙이면,
    ///    줄무늬 수십 개가 길이/두께/aspect 게이트를 전부 통과해 칠이 층층이 재합성된다(실전 보고).
    ///    응답(적분 best) 세기 순으로 정렬해 최강 컴포넌트(사용자가 노린 결함)는 무조건 채택하고,
    ///    누적 페인트가 max(최강×3, 칠 면적×8%)를 넘는 나머지는 버린다.
    ///  ② 전체(먼지+스크래치) 페인트 총량 ≤ 칠 면적×40% — 어떤 조합으로도 칠 면적이 통째로
    ///    재합성될 수 없다(각 카테고리 최강 1개는 예산과 무관하게 항상 채택 — 결함 제거 보장).
    static let scratchBudgetLargestMultiple = 3.0
    static let scratchBudgetAreaFraction = 0.08
    static let totalBudgetAreaFraction = 0.40

    /// - dustStrong: 먼지 히스테리시스 코어(hard) 마스크. 주어지면 dust(=soft) 연결요소 중 strong
    ///   픽셀을 하나라도 포함한 것만 채택한다 — 컨텍스트 게이트에 걸린(주변도 비슷하게 강한) 디테일
    ///   섬/구조물은 코어가 없어 기각되고, soft 연결성 덕에 텍스처 카펫은 거대 컴포넌트로 묶여
    ///   면적/aspect 게이트에서 통째로 기각된다.
    /// - scratchResponse/regionArea: 브러시 경로 전용 와이프 퓨즈 입력(위 상수 주석 참조).
    ///   regionArea 가 nil 이면 퓨즈는 비활성(전역 자동/테스트 경로 — 기존 동작 그대로).
}
