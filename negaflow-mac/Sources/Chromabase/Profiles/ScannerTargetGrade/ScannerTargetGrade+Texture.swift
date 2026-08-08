import CoreImage

extension ScannerTargetGrade {
    // MARK: HS-1800 스타일 장치 질감(샤픈) — 설계 의도
    //
    // 이 타겟이 지향하는 질감 캐릭터(자체 설계 의도):
    //  • 이 계열 스캔은 기본 샤프닝이 늘 걸려 그레인이 또렷하고 선명하게 보이는 것이
    //    시그니처다. 흑백에서 그레인 강조가 특히 두드러진다.
    //  • 부드러운 렌더링을 지향하는 FUJI 타겟에는 샤픈을 얹지 않는다. MAIN/PRINT 는
    //    정직한 플랫 마스터 계약이라 질감을 굽지 않는다.
    //  • 정확한 반경/강도 수치는 공개 문서에 없다. 아래 상수는 "뚜렷이 보이되 sandpaper 가
    //    되지 않는" 문서 방향의 보수적 재현이며, 그레인은 합성하지 않는다 — 실제 필름
    //    그레인을 luminance USM 이 crisp 하게 만드는 것이 실기와 같은 메커니즘이다.
    //
    // 구현: 커스텀 noritsuTexture 커널(감마 도메인 luminance USM). CISharpenLuminance 는
    // linear 작업공간에서 동작해 (1) 암부 언더슈트가 0 크러시(히스토그램 0-빈 폭발 계약 위반),
    // (2) 명부 오버슈트가 unit range 이탈(IT8 unit cube 계약 위반)을 만들었다. 커널은 장치
    // 출력 도메인(감마)에서 luma 만 움직이고 undershoot 플로어·유닛 상한·extended 통과·hue
    // 보존 가드를 내장한다. 색 프린지 없음. 장치 샤프닝은 스캔 단계 속성이므로 필름 타입
    // 전체(컬러/흑백 × 네거티브/슬라이드)에 동일 적용한다.

    /// 가우시안 저역 시그마(px). 실기 USM 반경의 보수적 재현.
    static let noritsuSharpenRadius = 0.9
    /// 감마 도메인 USM 게인.
    static let noritsuSharpenAmount = 0.6

    static func applyDocumentedTexture(to image: CIImage, target: DevelopTarget) -> CIImage {
        guard target == .noritsu,
              let kernel = ChromabaseMetalKernels.colorKernel(named: "noritsuTexture") else {
            return image
        }
        let extent = image.extent
        let blurred = image.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [
                kCIInputRadiusKey: noritsuSharpenRadius,
            ])
            .cropped(to: extent)
        return kernel.apply(
            extent: extent,
            arguments: [image, blurred, Float(noritsuSharpenAmount)]
        )?.cropped(to: extent) ?? image
    }
}
