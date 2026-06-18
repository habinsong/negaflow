import Foundation
import CoreImage

// MARK: - ToneMapper (plan §8.7)
//
// density / highlight roll-off / black softness / contrast를 다룬다.
// 필름 스캔에서 중요한 건 density, roll-off, black softness다 (plan §8.7).
public enum ToneMapper {
    /// 노출(stops) 보정. gamma로 근사.
    public static func applyExposure(to image: CIImage, stops: Double) -> CIImage {
        guard abs(stops) > 1e-3 else { return image }
        // +1 stop = ×2 선형 = gamma 0.5 근사가 아님; 선형 곱이 정확.
        let factor = pow(2.0, stops)
        return image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: CGFloat(factor), y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: CGFloat(factor), z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: CGFloat(factor), w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0),
        ])
    }

    /// 톤 커브: density / highlight roll-off / shadow softness.
    public static func applyToneCurves(to image: CIImage, params: DevelopParameters) -> CIImage {
        var img = image
        let extent = image.extent

        // Density: 중간톤 밀도. 대비 + 미드톤 리프트로 근사.
        // density > 0 → 더 쫀득한 인화 느낌 (plan §8.9 Rich Neutral).
        if abs(params.density) > 1e-3 {
            let contrast = 1.0 + params.density * 0.22
            let brightness = params.density * 0.02
            img = img.applyingFilter("CIColorControls", parameters: [
                "inputContrast": NSNumber(value: contrast),
                "inputBrightness": NSNumber(value: brightness),
                "inputSaturation": 1.0,
            ])
        }

        // Highlight roll-off: 하이라이트 부드럽게 깎기.
        // 라이트 쪽 감마를 올려 하이라이트를 압축.
        if abs(params.highlight) > 1e-3 {
            // highlight > 0 → 하이라이트 회복(감마 올림), < 0 → 더 자극적으로
            let power = 1.0 - params.highlight * 0.35
            let clampedPow = max(0.45, min(1.6, power))
            img = img.applyingFilter("CIGammaAdjust", parameters: [
                "inputPower": NSNumber(value: clampedPow),
            ])
        }

        // Shadow softness: 섀도우가 막히지 않게 리프트.
        if abs(params.shadow) > 1e-3 {
            // shadow > 0 → 섀도우 열기(블랙 포인트 올림), < 0 → 더 깊게
            let blackPoint = max(-0.15, min(0.15, params.shadow * 0.12))
            // CIColorControls는 음수 밝기로 흑점을 내리는 효과; 리프트는 오프셋으로.
            if params.shadow > 0 {
                img = img.applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: 1, w: 0),
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                    "inputBiasVector": CIVector(x: CGFloat(blackPoint), y: CGFloat(blackPoint),
                                                z: CGFloat(blackPoint), w: 0),
                ])
            } else {
                img = img.applyingFilter("CIColorControls", parameters: [
                    "inputBrightness": NSNumber(value: blackPoint),
                    "inputContrast": 1.0,
                    "inputSaturation": 1.0,
                ])
            }
        }

        return img.clamped(to: extent)
    }
}
