import Foundation
import CoreImage

// MARK: - ColorModel (plan §8.8)
//
// warmth / tint / colorDepth(채도) / 채널 균형.
// 네거티브 반전 직후와 톤 매핑 전에 적용된다.
public enum ColorModel {
    public static func apply(to image: CIImage, params: DevelopParameters) -> CIImage {
        var img = image

        // Warmth: 온도. R/B 균형 이동. warmth > 0 → 따뜻하게(R↑ B↓).
        if abs(params.warmth) > 1e-3 {
            let r = 1.0 + params.warmth * 0.18
            let b = 1.0 - params.warmth * 0.18
            let g = 1.0 + params.warmth * 0.03
            img = img.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: CGFloat(r), y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: CGFloat(g), z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: CGFloat(b), w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            ])
        }

        // Tint: 녹/마젠타 축. G vs (R+B) 균형.
        if abs(params.tint) > 1e-3 {
            let g = 1.0 + params.tint * 0.24
            let rb = 1.0 - params.tint * 0.12
            img = img.applyingFilter("CIColorMatrix", parameters: [
                "inputGVector": CIVector(x: 0, y: CGFloat(g), z: 0, w: 0),
                "inputRVector": CIVector(x: CGFloat(rb), y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: CGFloat(rb), w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            ])
        }

        // Color depth / saturation.
        if abs(params.colorDepth) > 1e-3 {
            let sat = 1.0 + params.colorDepth * 0.35
            img = img.applyingFilter("CIColorControls", parameters: [
                "inputSaturation": NSNumber(value: sat),
                "inputContrast": 1.0,
                "inputBrightness": 0.0,
            ])
        }

        if abs(params.vibrance) > 1e-3 {
            img = applyVibrance(to: img, amount: params.vibrance * 0.8)
        }

        if abs(params.saturation) > 1e-3 {
            img = img.applyingFilter("CIColorControls", parameters: [
                "inputSaturation": NSNumber(value: 1.0 + params.saturation * 0.6),
                "inputContrast": 1.0,
                "inputBrightness": 0.0,
            ])
        }

        if abs(params.redPrimary) > 1e-3 || abs(params.greenPrimary) > 1e-3 || abs(params.bluePrimary) > 1e-3 {
            let r = 1.0 + params.redPrimary * 0.16
            let g = 1.0 + params.greenPrimary * 0.16
            let b = 1.0 + params.bluePrimary * 0.16
            img = img.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: CGFloat(r), y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: CGFloat(g), z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: CGFloat(b), w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            ])
        }

        return img
    }

    private static func applyVibrance(to image: CIImage, amount: Double) -> CIImage {
        if let filter = CIFilter(name: "CIVibrance") {
            filter.setValue(image, forKey: kCIInputImageKey)
            filter.setValue(amount, forKey: "inputAmount")
            return filter.outputImage ?? image
        }
        return image.applyingFilter("CIColorControls", parameters: [
            "inputSaturation": NSNumber(value: 1.0 + amount * 0.25),
            "inputContrast": 1.0,
            "inputBrightness": 0.0,
        ])
    }
}

// MARK: - TextureStage (plan §8.10 texture)
//
// Grain / Sharpness / Halation. MVP에서는 가볍게.
public enum TextureStage {
    public static func apply(to image: CIImage, params: DevelopParameters) -> CIImage {
        var img = image

        // Sharpness: 언샤프 마스크. 약하게.
        if params.sharpness > 1e-3 {
            let radius = 1.5 + params.sharpness * 2.5
            let intensity = 0.3 + params.sharpness * 0.6
            img = img.applyingFilter("CIUnsharpMask", parameters: [
                "inputRadius": NSNumber(value: radius),
                "inputIntensity": NSNumber(value: intensity),
            ])
        }

        // Grain: 노이즈 오버레이. 미세하게.
        if params.grain > 1e-3 {
            let extent = image.extent
            // CIRandomGenerator는 inputExtent를 지원하지 않는다 — 출력을 crop한다.
            let noise = CIFilter(name: "CIRandomGenerator")?.outputImage?
                .cropped(to: extent)
            if let noise {
                let monochromeNoise = noise.applyingFilter("CIColorControls", parameters: [
                    "inputSaturation": 0.0,
                ]).applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: CGFloat(params.grain * 0.06), y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: CGFloat(params.grain * 0.06), z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: CGFloat(params.grain * 0.06), w: 0),
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                ])
                img = img.composited(over: monochromeNoise.cropped(to: extent))
            }
        }

        if abs(params.clarity) > 1e-3 {
            if params.clarity > 0 {
                img = img.applyingFilter("CIUnsharpMask", parameters: [
                    "inputRadius": NSNumber(value: 6.0 + params.clarity * 6.0),
                    "inputIntensity": NSNumber(value: 0.18 + params.clarity * 0.35),
                ])
            } else {
                img = img.applyingFilter("CIColorControls", parameters: [
                    "inputSaturation": 1.0,
                    "inputContrast": NSNumber(value: 1.0 + params.clarity * 0.18),
                    "inputBrightness": 0.0,
                ])
            }
        }

        // Halation: 하이라이트 주변의 은은 발산. 가우시안 블러 + screen 합성.
        if params.halation > 1e-3 {
            let blurred = img.applyingFilter("CIGaussianBlur", parameters: [
                "inputRadius": NSNumber(value: 4 + params.halation * 10),
            ])
            let luma = img.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
                "inputGVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
                "inputBVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            ])
            let highlightMask = luma
                .applyingFilter("CIColorControls", parameters: [
                    "inputSaturation": 0.0,
                    "inputContrast": 4.0,
                    "inputBrightness": -0.55,
                ])
                .applyingFilter("CIColorClamp", parameters: [
                    "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 1),
                    "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1),
                ])
                .cropped(to: img.extent)
            let bright = blurred.applyingFilter("CIColorControls", parameters: [
                "inputBrightness": NSNumber(value: 0.1 + params.halation * 0.15),
                "inputContrast": NSNumber(value: 0.2),
                "inputSaturation": 0.8,
            ])
            let screened = CIFilter(name: "CIScreenBlendMode", parameters: [
                kCIInputImageKey: bright.cropped(to: img.extent),
                kCIInputBackgroundImageKey: img,
            ])?.outputImage ?? img
            img = screened.applyingFilter("CIBlendWithMask", parameters: [
                "inputBackgroundImage": img,
                "inputMaskImage": highlightMask,
            ])
        }

        if abs(params.vignette) > 1e-3,
           let filter = CIFilter(name: "CIVignette") {
            filter.setValue(img, forKey: kCIInputImageKey)
            filter.setValue(params.vignette * 1.8, forKey: "inputIntensity")
            filter.setValue(min(image.extent.width, image.extent.height) * 0.45, forKey: "inputRadius")
            img = filter.outputImage ?? img
        }

        return img.cropped(to: image.extent)
    }
}
