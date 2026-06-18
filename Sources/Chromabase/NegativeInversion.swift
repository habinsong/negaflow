import Foundation
import CoreImage

// MARK: - NegativeInversion (plan §8.6)
//
// 단순 1 - RGB 반전은 금지한다 (plan §8.6).
// 스캔 값은 투과광 기준이므로 density-like transform을 사용한다.
//
// Algorithm B (density-like invert) — MVP 기본 채택:
//   1. film base로 채널별 정규화:  t_c = clamp(I_c / base_c)
//   2. 밀도 근사:                 d_c = 1 - pow(t_c, gamma)
//   3. 톤 매핑:                   out_c = tonemap(d_c)
//
// 이 방식은 단순 반전보다 하이라이트/섀도우에서 부드럽고,
// 오렌지 마스크 제거가 자연스럽다.
public enum NegativeInversion {
    /// density-based 네거티브 반전을 적용한 CIImage를 반환한다.
    public static func apply(to image: CIImage, base: FilmBase) -> CIImage {
        // Core Image 커스텀 컬러 매트릭스로는 log 변환을 직접 표현하기 어렵다.
        // 대신 t = I / base, out = 1 - pow(t, gamma)로 density 응답을 근사한다.
        // clear base(t≈1)는 검은 기준점, 밀도가 높은 어두운 네거티브(t↓)는 밝은 양화가 된다.

        let scale = SIMD3(1.0 / max(1e-3, base.rgb.x),
                          1.0 / max(1e-3, base.rgb.y),
                          1.0 / max(1e-3, base.rgb.z))

        let normalized = image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: CGFloat(scale.x), y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: CGFloat(scale.y), z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: CGFloat(scale.z), w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0),
        ]).applyingFilter("CIColorClamp", parameters: [
            "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1),
        ]).cropped(to: image.extent)

        let densityGamma = 0.72
        let curved = normalized.applyingFilter("CIGammaAdjust", parameters: [
            "inputPower": densityGamma,
        ])

        let inverted = curved.applyingFilter("CIColorInvert")
        let soft = inverted.applyingFilter("CIColorControls", parameters: [
            "inputBrightness": 0.0,
            "inputContrast": 1.02,
            "inputSaturation": 1.0,
        ])
        return soft.cropped(to: image.extent)
    }
}
