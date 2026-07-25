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
            let r = 1.0 + params.redPrimary * 0.32
            let g = 1.0 + params.greenPrimary * 0.32
            let b = 1.0 + params.bluePrimary * 0.32
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

        // Sharpness: 휘도 엣지 강조. 기존(radius 1.5~4.0, intensity 0.3~0.9)은 너무 공격적이라
        // 스캐너 노이즈를 증폭해 "TV 화면 노이즈"처럼 보였다. radius/intensity를 낮춰 과증폭을 막는다.
        if params.sharpness > 1e-3 {
            let radius = 1.0 + params.sharpness * 1.2
            let intensity = 0.18 + params.sharpness * 0.42
            img = img.applyingFilter("CIUnsharpMask", parameters: [
                "inputRadius": NSNumber(value: radius),
                "inputIntensity": NSNumber(value: intensity),
            ]).cropped(to: image.extent)
        }

        // Grain: zero-mean 휘도가중 노이즈 커널. CIRandomGenerator는 inputExtent를 지원하지
        // 않으므로 출력을 crop해 src와 좌표를 맞춘다.
        if params.grain > 1e-3,
           let kernel = ChromabaseMetalKernels.colorKernel(named: "filmGrain"),
           let noise = CIFilter(name: "CIRandomGenerator")?.outputImage?.cropped(to: image.extent) {
            let amount = Float(params.grain * 0.055)
            img = kernel.apply(extent: image.extent, arguments: [img, noise, amount])?
                .cropped(to: image.extent) ?? img
        }

        // Clarity: 국소(미드톤) 대비.
        //  + : 큰 반경 언샤프로 국소 대비↑. 기존(intensity 최대 0.53)은 노이즈/샤픈처럼 과했다.
        //  − : 전역 대비 축소(기존)는 흑·백점을 가운데로 당겨 화면 전체가 회색으로 떴다. 대신
        //      블러본으로 수렴시켜 국소 대비만 부드럽게 낮춘다(흑/백점 보존).
        if abs(params.clarity) > 1e-3 {
            if params.clarity > 0 {
                img = img.applyingFilter("CIUnsharpMask", parameters: [
                    "inputRadius": NSNumber(value: 6.0 + params.clarity * 5.0),
                    "inputIntensity": NSNumber(value: 0.10 + params.clarity * 0.18),
                ]).cropped(to: image.extent)
            } else {
                let amount = min(0.9, -params.clarity * 0.8)
                let blurred = img.applyingFilter("CIGaussianBlur", parameters: [
                    "inputRadius": NSNumber(value: 4.0 - params.clarity * 6.0),
                ]).cropped(to: image.extent)
                img = CIFilter(name: "CIDissolveTransition", parameters: [
                    kCIInputImageKey: img,
                    kCIInputTargetImageKey: blurred,
                    kCIInputTimeKey: amount,
                ])?.outputImage?.cropped(to: image.extent) ?? img
            }
        }

        // Halation: 필름 안티할레이션 층 특성 — 명부에서 새어나오는 **붉은/주황 글로우**.
        // 기존엔 desat 블러를 명부에 screen 합성해 명부를 그냥 하얗게 만들었다(사용자 지적).
        // 여기선 명부만 추출→블러→웜 틴트(R↑B↓)→약하게 screen 가산해, 밝은 디테일 주변에
        // 따뜻한 발산을 더한다(순검정 프레임은 명부가 없어 들뜨지 않음).
        if params.halation > 1e-3 {
            let h = CGFloat(params.halation)
            // 명부 추출: luma를 강한 대비/오프셋으로 thresholding → 명부=1, 그 외=0 마스크.
            let luma = img.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
                "inputGVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
                "inputBVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            ])
            let highlightMask = luma.applyingFilter("CIColorControls", parameters: [
                "inputSaturation": 0.0,
                "inputContrast": 4.0,
                "inputBrightness": -0.42,
            ]).applyingFilter("CIColorClamp", parameters: [
                "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1),
            ]).cropped(to: img.extent)
            // 명부만 남긴 이미지(나머지는 검정)를 블러해 발산을 만든다.
            let highlightsOnly = CIFilter(name: "CIBlendWithMask", parameters: [
                kCIInputImageKey: img,
                kCIInputBackgroundImageKey: CIImage(color: .black).cropped(to: img.extent),
                "inputMaskImage": highlightMask,
            ])?.outputImage?.cropped(to: img.extent) ?? img
            let glow = highlightsOnly.applyingFilter("CIGaussianBlur", parameters: [
                "inputRadius": NSNumber(value: 5.0 + h * 12.0),
            ]).cropped(to: img.extent)
            // 웜 틴트 + 강도 스케일(붉은 발산). 강도를 낮춰 명부 백화 대신 은은한 글로우로.
            let warmGlow = glow.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0.85 * h, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 0.40 * h, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0.18 * h, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            ]).cropped(to: img.extent)
            img = CIFilter(name: "CIScreenBlendMode", parameters: [
                kCIInputImageKey: warmGlow,
                kCIInputBackgroundImageKey: img,
            ])?.outputImage?.cropped(to: img.extent) ?? img
        }

        if abs(params.vignette) > 1e-3,
           let mask = radialEdgeMask(for: image.extent) {
            if params.vignette > 0 {
                let edgeScale = 1.0 - params.vignette * 0.42
                let darkened = img.applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: edgeScale, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: edgeScale, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: edgeScale, w: 0),
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                ]).cropped(to: image.extent)
                img = darkened.applyingFilter("CIBlendWithMask", parameters: [
                    "inputBackgroundImage": img,
                    "inputMaskImage": mask,
                ]).cropped(to: image.extent)
            } else {
                let edgeLift = -params.vignette * 0.16
                let lifted = img.applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: 1, w: 0),
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                    "inputBiasVector": CIVector(x: edgeLift, y: edgeLift, z: edgeLift, w: 0),
                ]).applyingFilter("CIColorClamp", parameters: [
                    "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 1),
                    "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1),
                ]).cropped(to: image.extent)
                img = lifted.applyingFilter("CIBlendWithMask", parameters: [
                    "inputBackgroundImage": img,
                    "inputMaskImage": mask,
                ]).cropped(to: image.extent)
            }
        }

        return img.cropped(to: image.extent)
    }

    private static func radialEdgeMask(for extent: CGRect) -> CIImage? {
        let minDimension = min(extent.width, extent.height)
        return CIFilter(name: "CIRadialGradient", parameters: [
            "inputCenter": CIVector(x: extent.midX, y: extent.midY),
            "inputRadius0": NSNumber(value: minDimension * 0.34),
            "inputRadius1": NSNumber(value: minDimension * 0.72),
            "inputColor0": CIColor(red: 0, green: 0, blue: 0, alpha: 1),
            "inputColor1": CIColor(red: 1, green: 1, blue: 1, alpha: 1),
        ])?.outputImage?.cropped(to: extent)
    }
}
