import Foundation
import CoreImage

// MARK: - ColorModel (plan §8.8)
//
// warmth / tint / colorDepth(채도) / 채널 균형.
// 네거티브 반전 직후와 톤 매핑 전에 적용된다.
public enum ColorModel {
    public static func apply(to image: CIImage, params: DevelopParameters) -> CIImage {
        var img = image

        // Warmth(온도, + = 따뜻하게 R↑ B↓) · Tint(녹/마젠타, + = 녹색). 휘도 중립 게인 하나로 적용한다
        // (WhiteBalanceGains — ±1 까지 예전 채널비, 그 너머는 로그 연장).
        if let wb = WhiteBalanceGains.gains(warmth: params.warmth, tint: params.tint) {
            img = img.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: CGFloat(wb.x), y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: CGFloat(wb.y), z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: CGFloat(wb.z), w: 0),
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
// Clarity / Sharpness / Grain / Halation / Vignette.
public enum TextureStage {
    public static func apply(to image: CIImage, params: DevelopParameters) -> CIImage {
        var img = image

        // 부분 대비 → 선명도 → 그레인 순서다. 그레인은 합성 질감이라 앞의 두 단계가 키우지 않게
        // 마지막에 얹는다(라이트룸도 명료도는 기본 패널, 선명도는 디테일 패널 끝).
        if params.developTarget == .sp3000 {
            img = DetailEnhancement.localContrast(img, clarity: ScannerTargetGrade.spLocalContrast)
        }
        img = DetailEnhancement.localContrast(img, clarity: params.clarity)
        img = DetailEnhancement.sharpen(img, sharpness: params.sharpness)

        // Grain: zero-mean 휘도가중 노이즈 커널. CIRandomGenerator는 inputExtent를 지원하지
        // 않으므로 출력을 crop해 src와 좌표를 맞춘다.
        if params.grain > 1e-3,
           let kernel = ChromabaseMetalKernels.colorKernel(named: "filmGrain"),
           let noise = CIFilter(name: "CIRandomGenerator")?.outputImage?.cropped(to: image.extent) {
            let amount = Float(params.grain * 0.055)
            img = kernel.apply(extent: image.extent, arguments: [img, noise, amount])?
                .cropped(to: image.extent) ?? img
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
