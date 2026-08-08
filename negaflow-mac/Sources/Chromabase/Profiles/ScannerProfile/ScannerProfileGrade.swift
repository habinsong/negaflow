import CoreImage

public enum ScannerProfileGrade {
    struct Parameters: Equatable, Sendable {
        let gamma: Double
        let contrastAmount: Double
        let saturation: Double
        let vibrance: Double
        let redGain: Double
        let greenGain: Double
        let blueGain: Double
        let shadowPoint: Double
        let midPoint: Double
        let highlightPoint: Double
        let unsharp: Double
        let parameterClampTriggered: Bool
    }

    static func parameters(for profile: ScannerProfile) -> Parameters {
        var clampTriggered = false
        func bounded(_ value: Double, _ low: Double, _ high: Double) -> Double {
            let result = clamp(value, low, high)
            if result != value { clampTriggered = true }
            return result
        }

        let p10 = bounded(profile.tone["p10"]?.median ?? 0.10, 0.0, 1.0)
        let p50 = bounded(profile.tone["p50"]?.median ?? 0.55, 0.0, 1.0)
        let p90 = bounded(profile.tone["p90"]?.median ?? 0.90, 0.0, 1.0)
        let contrast = bounded(
            profile.tone["contrast_p90_p10"]?.median ?? (p90 - p10),
            0.0,
            1.0
        )
        let midRG = profile.color["mid_rg"]?.median ?? 0
        let midGB = profile.color["mid_gb"]?.median ?? 0
        let midChroma = profile.color["mid_chroma"]?.median ?? 20
        let sharpness = profile.texture["texture_sharpness_p95"]?.median ?? 0.5
        let isSlide = profile.kind == "color slide"
        let satBase = isSlide ? 1.07 : 1.03
        let k = 0.55

        return Parameters(
            gamma: bounded(0.98 + (0.56 - p50) * 0.14, 0.88, 1.08),
            contrastAmount: bounded(1.06 + (contrast - 0.72) * 0.55, 1.00, 1.22),
            saturation: bounded(
                satBase + (midChroma - 24.0) / 450.0,
                isSlide ? 1.02 : 0.99,
                isSlide ? 1.16 : 1.10
            ),
            vibrance: bounded(0.04 + (midChroma - 24.0) / 800.0, 0.0, 0.14),
            redGain: bounded(1.0 + midRG / 255.0 * k, 0.94, 1.06),
            greenGain: bounded(
                1.0 - midRG / 255.0 * (k * 0.34) + midGB / 255.0 * (k * 0.32),
                0.94,
                1.06
            ),
            blueGain: bounded(1.0 - midGB / 255.0 * k, 0.94, 1.06),
            shadowPoint: bounded(0.215 + (p10 - 0.11) * 0.22, 0.175, 0.255),
            midPoint: bounded(0.505 + (p50 - 0.55) * 0.12, 0.455, 0.560),
            highlightPoint: bounded(0.830 + (p90 - 0.88) * 0.12, 0.795, 0.875),
            unsharp: bounded((sharpness - 0.38) * 0.62, 0.0, 0.38),
            parameterClampTriggered: clampTriggered
        )
    }

    public static func apply(to image: CIImage, profile: ScannerProfile) -> CIImage {
        let extent = image.extent
        let parameters = parameters(for: profile)

        // Saturation — `mid_chroma` is a roll-wide median, so it reflects how vivid the
        // SCENES in that roll happened to be, not a property of the film. Driving saturation
        // directly off it cranked vivid rolls (e.g. SP-3000 Ektar, mid_chroma≈62) to ×1.46
        // and blew neutral frames into magenta/purple. Use a gentle film-class base with only
        // a whisper of chroma modulation, tightly clamped, so no frame is over-saturated.
        // Film hue character — per-channel balance toward the film's mid R−G / G−B, so distinct
        // films (e.g. yellow-leaning Ektar vs blue-leaning UltraMax) separate visibly. A global
        // gain would also tint the white point (the green/cyan-sky artifact), so this is applied
        // with highlight preservation (see applyFilmTint) and bounded to ±6%.
        var out = image
            .applyingFilter("CIGammaAdjust", parameters: ["inputPower": parameters.gamma])
            .applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: parameters.saturation,
                kCIInputContrastKey: parameters.contrastAmount,
            ])
        if parameters.vibrance > 1e-3 {
            out = out.applyingFilter("CIVibrance", parameters: [
                "inputAmount": parameters.vibrance,
            ])
        }
        out = applyFilmTint(
            to: out,
            red: parameters.redGain,
            green: parameters.greenGain,
            blue: parameters.blueGain
        )
        out = out
            .applyingFilter("CIToneCurve", parameters: [
                "inputPoint0": CIVector(x: 0.00, y: 0.00),
                "inputPoint1": CIVector(x: 0.23, y: parameters.shadowPoint),
                "inputPoint2": CIVector(x: 0.50, y: parameters.midPoint),
                "inputPoint3": CIVector(x: 0.82, y: parameters.highlightPoint),
                "inputPoint4": CIVector(x: 1.00, y: 1.00),
            ])
        if parameters.unsharp > 0 {
            out = out.applyingFilter("CIUnsharpMask", parameters: [
                "inputRadius": 1.8,
                "inputIntensity": parameters.unsharp,
            ])
        }
        return out
            .applyingFilter("CIColorClamp", parameters: [
                "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1),
            ])
            .cropped(to: extent)
    }

    /// Apply a gentle per-channel film hue balance, but keep neutral highlights neutral.
    /// A flat per-channel gain tints the white point (the green/cyan-sky artifact); here the
    /// tint is blended back out as luma approaches white, so bright skies stay neutral while
    /// mid/shadow tones still carry the film's character.
    private static func applyFilmTint(to image: CIImage,
                                      red: Double, green: Double, blue: Double) -> CIImage {
        let extent = image.extent
        let tinted = image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: red, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: green, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: blue, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ]).cropped(to: extent)
        // Highlight mask: 0 below `lo` (full tint), ramping to 1 by `hi` (revert to neutral).
        // `hi` is kept well below white so bright skies see no tint at all.
        let lo = 0.50, hi = 0.72
        let scale = 1.0 / (hi - lo)
        let highlightMask = image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
            "inputGVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
            "inputBVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ]).applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: scale, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: scale, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: scale, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: -lo * scale, y: -lo * scale, z: -lo * scale, w: 0),
        ]).applyingFilter("CIColorClamp", parameters: [
            "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1),
        ]).cropped(to: extent)
        // mask=1 → original (neutral highlight); mask=0 → tinted (mid/shadow film character).
        return CIFilter(name: "CIBlendWithMask", parameters: [
            kCIInputImageKey: image,
            kCIInputBackgroundImageKey: tinted,
            "inputMaskImage": highlightMask,
        ])?.outputImage?.cropped(to: extent) ?? tinted
    }

    private static func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double {
        min(max(value, low), high)
    }
}
