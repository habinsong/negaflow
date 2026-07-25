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
        img = FilmEmulationStage.apply(
            to: img,
            emulation: params.filmEmulation,
            intensity: params.filmEmulationIntensity
        )

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
        img = TextureStage.apply(to: img, params: params)

        // 10. B&W 필름은 모든 컬러 그레이딩/그레인 이후 최종적으로 중립 그레이스케일로 변환한다.
        //     (그레인/텍스처가 채널별로 색 얼룩을 더하므로 반드시 마지막 단계에서 적용.)
        //     측정된 장비별 흑백 틴트가 생기면 중립화 뒤, 사용자 토닝 앞에 얹는다.
        //     현재 번들에는 해당 paired evidence가 없으므로 이 단계는 no-op이다.
        if params.filmType == .bwNegative || params.filmType == .bwPositive {
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
}
