import Foundation

extension ScannerTargetGrade {
    // MARK: 타깃별 렌더링 표
    //
    // 근거와 한계(2026-11-03 재설계):
    //  • SP: 같은 네거티브를 SP-3000(랩 JPEG)과 OpticFilm+MAIN 으로 스캔한 짝 4장(화소 정합,
    //    ΔE00 로 맞춤)이 주 근거다. 톤은 짝 0.75 + 실기 SP 5롤 185컷 백분위 분포 0.25 로 섞었다
    //    (짝은 한 롤, 분포는 다른 네거티브라 각자 편향이 있다). 채도는 밝기별 게인만 두고
    //    크로스토크·회색축 오프셋은 쓰지 않는다 — 짝에서 롤 밸런스가 ≈0 이었고, 그 이상을
    //    맞추면 이 롤의 MAIN 치우침을 배운다(홀드아웃으로 확인). 짝 홀드아웃 ΔE00 중앙값 평균
    //    3.9(같은 짝에서 MAIN 7.4, 이전 SP 7.0).
    //  • HS(NORITSU): 짝 스캔이 없다. 같은 라벨 롤 3쌍(Ektar×2, Portra 160)을 두 기종이 스캔한
    //    통계의 차이(중앙값)를 SP 위에 얹었다: 미드 −0.04~−0.08 코드, 최상단 +0.02, 채색 화소
    //    채도 ×0.88, 회색축 a* −0.7~−4(밝을수록 초록 쪽). 절대 분포는 롤 내용(야간 롤 등)에
    //    끌려 쓰지 않는다.
    //  • F135 / HR: 실기 데이터가 없다. 측정된 미니랩 렌더링(SP)에 Kodak Endura Premier
    //    (E-4070) 특성곡선의 토우를 SP 미드 위치·기울기에 맞춰 붙였다(Kodak 디지털 미니랩은
    //    균형 잡힌 농도를 인화지 특성곡선으로 매핑한다, US6233069). HR 은 같은 톤에 채도만
    //    ×0.92(프로 랩의 자연스러운 렌더링 서술). 실기 대조로 검증되지 않은 설계라 근거 없는
    //    차이를 더 얹지 않는다 — 대비를 낮추면 흰색이 .91 에 머물러 실기(.96)와 멀어진다.
    //  • 슬라이드는 renderingPositiveStrength 로 절반만 싣는다(실측 없음).

    static func rendering(for target: DevelopTarget) -> Rendering? {
        switch target {
        case .sp3000: return spRendering
        case .noritsu: return noritsuRendering
        case .f135: return f135Rendering
        case .hr: return hrRendering
        default: return nil
        }
    }

    private static let spRendering = Rendering(
        tone: [0.0464, 0.0734, 0.1025, 0.1370, 0.2044, 0.3105, 0.4671, 0.7152, 0.8381, 0.9540, 0.9780],
        chromaGain: [1.0, 1.0, 1.142, 1.375],
        crosstalk: [0, 0, 0, 0, 0, 0],
        redBalance: [0, 0, 0],
        blueBalance: [0, 0, 0]
    )

    private static let noritsuRendering = Rendering(
        tone: [0.0490, 0.0741, 0.1012, 0.1330, 0.1928, 0.2828, 0.4160, 0.6688, 0.8397, 0.9665, 0.9820],
        chromaGain: [0.8793, 0.8793, 1.0042, 1.2090],
        crosstalk: [0, 0, 0, 0, 0, 0],
        redBalance: [0.0778, -0.0737, -0.1429],
        blueBalance: [0.0326, -0.037, -0.0397]
    )

    private static let f135Rendering = Rendering(
        tone: [0.0486, 0.0519, 0.0673, 0.0917, 0.1554, 0.2781, 0.4671, 0.7152, 0.8381, 0.9540, 0.9780],
        chromaGain: [1.0, 1.0, 1.142, 1.375],
        crosstalk: [0, 0, 0, 0, 0, 0],
        redBalance: [0, 0, 0],
        blueBalance: [0, 0, 0]
    )

    private static let hrRendering = Rendering(
        tone: [0.0486, 0.0519, 0.0673, 0.0917, 0.1554, 0.2781, 0.4671, 0.7152, 0.8381, 0.9540, 0.9780],
        chromaGain: [0.92, 0.92, 1.0506, 1.265],
        crosstalk: [0, 0, 0, 0, 0, 0],
        redBalance: [0, 0, 0],
        blueBalance: [0, 0, 0]
    )
}
