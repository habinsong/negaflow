import CoreImage

enum ChromabaseMetalKernels {
    static func colorKernel(named name: String) -> CIColorKernel? {
        kernels[name] as? CIColorKernel
    }

    static var availableKernelNames: Set<String> {
        Set(kernels.keys)
    }

    private static let kernels: [String: CIKernel] = {
        do {
            return Dictionary(
                uniqueKeysWithValues: try CIKernel.kernels(withMetalString: source).map { ($0.name, $0) }
            )
        } catch {
            assertionFailure("Failed to compile Chromabase Metal kernels: \(error)")
            return [:]
        }
    }()

    private static let source = """
    #include <CoreImage/CoreImage.h>
    using namespace metal;

    [[stitchable]] float4 basicTone(
        coreimage::sample_t src,
        float contrastAmount,
        float densityAmount,
        float highlightAmount,
        float shadowAmount,
        float whitesAmount,
        float blacksAmount
    ) {
        float3 ycoef = float3(0.2126, 0.7152, 0.0722);
        float y = dot(src.rgb, ycoef);
        float target = y;

        float contrastPivot = 0.42;
        target = contrastPivot + (target - contrastPivot) * (1.0 + contrastAmount * 0.18);

        float midMask = smoothstep(0.08, 0.28, y) * (1.0 - smoothstep(0.56, 0.78, y));
        target -= densityAmount * 0.115 * midMask;

        float highlightMask = smoothstep(0.30, 0.58, y);
        target -= highlightAmount * 0.120 * highlightMask;

        float shadowMask = 1.0 - smoothstep(0.02, 0.30, y);
        target += shadowAmount * 0.030 * shadowMask;

        float whiteMask = smoothstep(0.28, 0.62, y);
        target += whitesAmount * 0.150 * whiteMask;

        float blackMask = 1.0 - smoothstep(0.00, 0.25, y);
        target += blacksAmount * 0.034 * blackMask;

        target = clamp(target, 0.0, 1.0);
        float3 rgb = src.rgb + float3(target - y);
        return float4(clamp(rgb, float3(0.0), float3(1.0)), src.a);
    }

    [[stitchable]] float4 parametricToneCurve(
        coreimage::sample_t src,
        float highlightsAmount,
        float lightsAmount,
        float darksAmount,
        float shadowsAmount,
        float shadowLow,
        float shadowHigh,
        float darkLow,
        float darkHigh,
        float lightLow,
        float lightHigh,
        float highlightLow,
        float highlightHigh
    ) {
        float3 ycoef = float3(0.2126, 0.7152, 0.0722);
        float y = dot(src.rgb, ycoef);

        float shadowMask = 1.0 - smoothstep(shadowLow, shadowHigh, y);
        float darkMask = smoothstep(shadowLow, shadowHigh, y) * (1.0 - smoothstep(darkLow, darkHigh, y));
        float lightMask = smoothstep(darkLow, darkHigh, y) * (1.0 - smoothstep(lightLow, lightHigh, y));
        float highlightMask = smoothstep(highlightLow, highlightHigh, y);

        float delta =
            shadowsAmount * 0.160 * shadowMask +
            darksAmount * 0.155 * darkMask +
            lightsAmount * 0.165 * lightMask +
            highlightsAmount * 0.150 * highlightMask;
        float target = clamp(y + delta, 0.0, 1.0);
        float3 rgb = src.rgb + float3(target - y);
        return float4(clamp(rgb, float3(0.0), float3(1.0)), src.a);
    }

    [[stitchable]] float4 scannerLowSatChroma(coreimage::sample_t src, coreimage::sample_t blur) {
        float3 ycoef = float3(0.2126, 0.7152, 0.0722);
        float y = dot(src.rgb, ycoef);
        float by = dot(blur.rgb, ycoef);
        float3 chroma = src.rgb - float3(y);
        float3 blurredChroma = blur.rgb - float3(by);
        float c = length(chroma);
        float lowSat = 1.0 - smoothstep(0.035, 0.160, c);
        float midHigh = smoothstep(0.24, 0.58, y);
        float magenta = smoothstep(0.006, 0.080, (src.r + src.b) * 0.5 - src.g);
        float amount = lowSat * midHigh * (0.38 + 0.42 * magenta);
        float3 mixedChroma = mix(chroma, blurredChroma, amount);
        mixedChroma = mix(mixedChroma, mixedChroma * 0.42, lowSat * magenta * 0.48);
        float3 rgb = clamp(float3(y) + mixedChroma, float3(0.0), float3(1.0));
        return float4(rgb, src.a);
    }

    [[stitchable]] float4 scannerMidtoneChroma(coreimage::sample_t src, coreimage::sample_t guided) {
        float3 ycoef = float3(0.2126, 0.7152, 0.0722);
        float y = dot(src.rgb, ycoef);
        float3 chroma = src.rgb - float3(y);
        float3 guidedChroma = guided.rgb - float3(0.5);
        guidedChroma -= float3(dot(guidedChroma, ycoef));
        float midtone = smoothstep(0.28, 0.48, y) * (1.0 - smoothstep(0.82, 0.94, y));
        float saturation = length(chroma);
        float colorNoise = smoothstep(0.040, 0.165, saturation);
        float warmPurple = smoothstep(0.015, 0.120, max(src.r - src.g, (src.r + src.b) * 0.5 - src.g));
        float speckle = smoothstep(0.010, 0.085, length(chroma - guidedChroma));
        float amount = midtone * colorNoise * (0.58 + 0.54 * warmPurple + 0.30 * speckle);
        float3 mixedChroma = mix(chroma, guidedChroma, clamp(amount, 0.0, 0.96));
        float axis = midtone * warmPurple;
        mixedChroma.r *= 1.0 - axis * 0.155;
        mixedChroma.b *= 1.0 - axis * 0.190;
        float3 rgb = clamp(float3(y) + mixedChroma, float3(0.0), float3(1.0));
        return float4(rgb, src.a);
    }

    [[stitchable]] float4 scannerDynamicRange(coreimage::sample_t src) {
        float y = dot(src.rgb, float3(0.2126, 0.7152, 0.0722));
        float shadow = 0.013 * (1.0 - smoothstep(0.00, 0.22, y));
        float deepToe = 1.0 - smoothstep(0.13, 0.31, y);
        float shoulder = smoothstep(0.72, 0.98, y);
        float compressedHigh = 0.72 + (y - 0.72) * 0.45;
        float targetY = mix(y + shadow - deepToe * 0.006, min(compressedHigh, 0.935), shoulder);
        float scale = targetY / max(y, 0.0005);
        float3 rgb = src.rgb * scale;
        float chromaFade = (1.0 - smoothstep(0.12, 0.38, targetY)) * 0.22;
        float midChromaFade = smoothstep(0.45, 0.66, targetY) * (1.0 - smoothstep(0.86, 0.96, targetY)) * 0.055;
        rgb = mix(rgb, float3(targetY), chromaFade + midChromaFade);
        rgb = clamp(rgb, float3(0.0), float3(1.0));
        return float4(rgb, src.a);
    }

    [[stitchable]] float4 scannerOutputGrade(coreimage::sample_t src) {
        float3 ycoef = float3(0.2126, 0.7152, 0.0722);
        float y = dot(src.rgb, ycoef);
        float3 chroma = src.rgb - float3(y);
        float c = length(chroma);

        float lowChroma = 1.0 - smoothstep(0.012, 0.050, c);
        float highlight = smoothstep(0.325, 0.385, y);
        float upperHighlight = smoothstep(0.358, 0.385, y);
        float pull = (0.072 * (1.0 - upperHighlight) + 0.003 * upperHighlight) * lowChroma * highlight;
        float targetY = max(0.0, y - pull);
        float3 rgb = src.rgb * (targetY / max(y, 0.0005));

        y = dot(rgb, ycoef);
        chroma = rgb - float3(y);
        c = length(chroma);
        lowChroma = 1.0 - smoothstep(0.018, 0.075, c);
        highlight = smoothstep(0.315, 0.430, y);
        float3 skyTint = float3(0.046, -0.028, 0.041);
        skyTint -= float3(dot(skyTint, ycoef));
        rgb += skyTint * (lowChroma * highlight * 0.70);

        y = dot(rgb, ycoef);
        chroma = rgb - float3(y);
        float midtone = smoothstep(0.070, 0.180, y) * (1.0 - smoothstep(0.48, 0.68, y));
        float warmPurple = smoothstep(0.010, 0.120, max(rgb.r - rgb.g, (rgb.r + rgb.b) * 0.5 - rgb.g));
        float axis = midtone * warmPurple * 0.90;
        chroma.r *= 1.0 - axis * 0.42;
        chroma.b *= 1.0 - axis * 0.48;
        rgb = float3(y) + chroma;

        return float4(clamp(rgb, float3(0.0), float3(1.0)), src.a);
    }
    """
}
