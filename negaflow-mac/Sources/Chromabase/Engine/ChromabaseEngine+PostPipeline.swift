import CoreGraphics
import CoreImage
import Foundation

extension ChromabaseEngine {
    func applyPostPipeline(
        to input: CIImage,
        params: DevelopParameters,
        extent: CGRect
    ) -> CIImage {
        var img = input

        // 8.4.x 고급 색/톤 — 포인트 커브 → HSL 믹서 → 색보정 → 캘리브레이션.
        //   톤 커브(휘도/RGB 포인트)는 색 조정 전에, 캘리브레이션은 마지막에.
        img = PointCurveStage.apply(to: img, curves: params.pointCurves)
        img = ColorMixerStage.apply(to: img, mixer: params.colorMixer)
        img = ColorGradingStage.apply(to: img, grading: params.colorGrading)
        img = CalibrationStage.apply(to: img, calibration: params.calibration)

        // 8.4.y 슬라이드 필름 특성 룩(좌측 Film 탭). 모든 사용자 색/톤 보정 뒤, 텍스처/그레인 전에
        //   얹는 창의적 최종 룩(데이터시트 유도 E100 / Velvia 50). 채도 부스트가 만든 out-of-gamut 는
        //   아래 최종 gamutSoftClip 이 hue 보존하며 정리한다.
        //   디지털 사진은 positive 도메인용 LUT로 톤·색을 한 번만 변환하고, 디지털 원본에 없는
        //   헐레이션·그레인만 별도로 보탠다. 이미 현상된 positive를 장면 노출로 되돌려 다시
        //   네거티브/슬라이드 현상하면 암부가 뜨고 톤 범위가 중앙으로 압축된다.
        //
        //   **필름 룩은 디지털 소스(Digital Color / Digital B&W) 전용이다.** 실제 필름을 스캔한
        //   경로(C-41 / ECN-2 / E-6 / D-76 / B&W Reversal)에는 걸리지 않는다 — 스캔본에는 이미
        //   그 유제를 통과한 신호가 들어 있어 유제 응답을 두 번 먹이는 셈이 되기 때문이다.
        //   흑백 프로세스에는 흑백 유제만, 컬러 프로세스에는 컬러 유제만 적용된다.
        if params.isDigitalSource == true {
            img = DigitalFilmLook.apply(
                to: img,
                emulation: params.filmEmulation,
                intensity: params.filmEmulationIntensity,
                grainOverride: params.grain,
                halationOverride: params.halation,
                monochrome: isMonochrome(params)
            )
        }

        // 8.5 소프트웨어 결함 제거 — 먼지/스크래치 제거. positive 상태에서 적용(임계값 의미 안정).
        if params.defectRemoval > 1e-3 {
            img = SoftwareDefectRemoval.apply(to: img, strength: params.defectRemoval)
        }

        // 8.6 사용자 노이즈 제거. 그레인/텍스처 **이전**에 적용. 필름 타입별 프로파일 연동.
        if params.noiseReduction > 1e-3 {
            img = FilmScanDenoise.apply(
                to: img,
                strength: params.noiseReduction,
                filmType: params.filmType,
                axes: FilmScanDenoise.Axes(
                    luma: params.noiseReductionLuma,
                    chroma: params.noiseReductionChroma,
                    darkTone: params.noiseReductionDarkTone,
                    detail: params.noiseReductionDetail,
                    grainProtect: params.noiseReductionGrainProtect
                )
            )
        }

        if !params.localDodgeBurn.isEmpty {
            img = LocalDodgeBurnStage.apply(to: img, adjustments: params.localDodgeBurn)
        }

        // 9. 텍스처
        //    디지털 소스에서 필름을 고르면 그레인과 헐레이션은 유제 물성으로 이미 얹혔다.
        //    같은 효과를 여기서 한 번 더 더하면 이중이 되므로 그 두 축만 비운다
        //    (선예도/명료도/비네팅은 사용자 조정이라 그대로 간다).
        img = TextureStage.apply(to: img, params: textureParameters(from: params))

        // 10. B&W 필름은 모든 컬러 그레이딩/그레인 이후 최종적으로 중립 그레이스케일로 변환한다.
        //     (그레인/텍스처가 채널별로 색 얼룩을 더하므로 반드시 마지막 단계에서 적용.)
        //     흑백 필름 룩이 이미 분광 가중치로 그레이를 합성했더라도 이 단계는 그대로 둔다 —
        //     이미 중립인 신호에 Rec.709 를 곱하면 항등이고, 뒤따르는 스테이지가 남긴 색 얼룩을
        //     청소하는 원래 역할은 유지되기 때문이다.
        //     측정된 장비별 흑백 틴트가 생기면 중립화 뒤, 사용자 토닝 앞에 얹는다.
        //     현재 번들에는 해당 paired evidence가 없으므로 이 단계는 no-op이다.
        if isMonochrome(params) {
            img = img.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
                "inputGVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
                "inputBVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            ]).cropped(to: extent)
            img = ScannerTargetGrade.applyMonochromeTint(to: img, params: params)
            img = BWToningStage.apply(to: img, toning: params.bwToning, filmType: params.filmType)
        }

        // 작업 이미지에서는 음수와 1 초과 값을 보존한다. 디스플레이/파일 gamut 매핑은
        // 목적 색공간을 아는 출력 경계가 담당해야 하며, 여기서 sRGB [0,1]로 강제하면
        // MAIN의 관용도와 유채색을 비가역적으로 잃는다.

        return ImageTransformStage.apply(
            to: img.cropped(to: extent),
            transform: params.imageTransform
        )
    }

    private func isMonochrome(_ params: DevelopParameters) -> Bool {
        params.filmType == .bwNegative || params.filmType == .bwPositive
    }

    /// 필름 룩이 실제로 걸린 경우에만 그레인/헐레이션 축을 비운 사본을 돌려준다.
    /// 그 조합에서는 두 효과를 필름 룩이 유제 물성으로 이미 적용했다. 룩이 걸리지 않았는데도
    /// 축을 비우면 사용자가 올려 둔 슬라이더가 조용히 무시된다.
    private func textureParameters(from params: DevelopParameters) -> DevelopParameters {
        guard params.isDigitalSource == true,
              DigitalFilmLook.appliesLook(emulation: params.filmEmulation,
                                          monochrome: isMonochrome(params)) else {
            return params
        }
        var stripped = params
        stripped.grain = 0
        stripped.halation = 0
        return stripped
    }
}
