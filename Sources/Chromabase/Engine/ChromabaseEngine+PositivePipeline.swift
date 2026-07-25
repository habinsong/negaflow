import CoreGraphics
import CoreImage
import Foundation

extension ChromabaseEngine {
    func applyPositiveFilmPipeline(
        to input: CIImage,
        params: DevelopParameters,
        sampleColorSpace: CGColorSpace,
        extent: CGRect
    ) -> CIImage {
        var img = input
        // 레인지 스트레치는 명시적 opt-in 전용이다. EXPIRED라는 이름만으로 압축된 장면 범위를
        // 열화 증거로 간주해 엔드포인트를 움직이지 않는다.
        if params.autoLevels {
            img = AutoLevels.apply(
                to: img,
                blackClip: 0.002,
                sampleColorSpace: sampleColorSpace,
                outputWhite: 0.86,
                outputBlack: 0.014
            )
        }
        // 스캐너 타겟은 해당 포지티브의 roll-label matched 상대 시그니처가 있을 때만
        // 독자 렌더링 베이스를 연다. 근거가 없으면 MAIN과 동일한 입력 보존 경로로 두어
        // 장치 이름만 붙은 가짜 포지티브 룩을 만들지 않는다.
        let hasScannerRelativeEvidence = !params.developTarget.isScannerEmulation
            || ScannerTargetGrade.resolveSignature(target: params.developTarget, params: params) != nil
        // MAIN/PRINT는 동일한 플랫 작업 이미지를 공유한다. 포지티브 고정 베이스 그레이드는
        // 측정 출력 ICC 이전에 룩을 중복시키므로 PRINT에는 적용하지 않는다.
        if params.developTarget.isScannerEmulation, hasScannerRelativeEvidence {
            img = PositiveDevelop.applyBaseGrade(to: img, filmType: params.filmType)
        }
        // EXPIRED는 명시적 중립축 측정 eligibility를 통과한 상대 보정만 적용한다.
        if params.developTarget == .rescue {
            let measureSpace = CGColorSpace(name: CGColorSpace.linearSRGB) ?? sampleColorSpace
            img = RescueGrade.apply(to: img, sampleColorSpace: measureSpace,
                                    filmType: params.filmType, recoverRange: false)
        }
        // 스캐너 타겟이면 문서 기반 개성을 항상 적용한다(포지티브도 감쇠 적용). applyBaseGrade(위)만
        // 보수적으로 실측 차분 증거에 게이팅해 독자 포지티브 베이스 중복을 막는다.
        if params.developTarget.isScannerEmulation {
            img = ScannerTargetGrade.apply(to: img, target: params.developTarget, params: params)
        } else if !params.developTarget.isScannerEmulation,
                  params.developTarget != .rescue,
                  let profile = scannerProfile(for: params) {
            img = ScannerProfileGrade.apply(to: img, profile: profile)
        }
        img = ColorModel.apply(to: img, params: params)
        img = ToneMapper.applyExposure(to: img, stops: params.exposure)
        img = ToneMapper.applyToneCurves(to: img, params: params)
        return img
    }
}
