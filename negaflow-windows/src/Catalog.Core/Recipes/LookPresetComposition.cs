namespace Negaflow.Catalog;

/// <summary>
/// 프리셋 위에 사용자 조절을 얹는 규칙입니다. macOS
/// <c>DevelopParameters.init(preset:overrides:)</c> 와 같습니다.
/// </summary>
/// <remarks>
/// 축마다 합치는 방법이 다르고, 그 차이가 곧 현상 결과입니다.
/// <list type="bullet">
/// <item>톤·색의 대부분은 <b>더합니다</b> — 프리셋이 시작점이고 사용자 값이 델타입니다.</item>
/// <item>grain·sharpness·halation 은 <b>큰 쪽을 씁니다</b>. 프리셋이 넣은 질감을 사용자가
/// 0 으로 두었다고 지우지 않기 위해서입니다.</item>
/// <item>point curve·color mixer·color grading·calibration 처럼 프리셋이 정의하지 않는
/// 축은 사용자 값을 <b>그대로</b> 씁니다.</item>
/// </list>
/// </remarks>
public static class LookPresetComposition
{
    /// <summary>프리셋 톤에 사용자 톤을 더합니다. 커브 네 축은 프리셋이 정하지 않으므로 그대로입니다.</summary>
    public static ToneAdjustment Compose(LookPreset preset, ToneAdjustment overrides)
    {
        ArgumentNullException.ThrowIfNull(preset);
        ToneAdjustment basis = preset.BaseTone;
        return new ToneAdjustment(
            Exposure: basis.Exposure + overrides.Exposure,
            Contrast: basis.Contrast + overrides.Contrast,
            CurveHighlights: overrides.CurveHighlights,
            CurveLights: overrides.CurveLights,
            CurveDarks: overrides.CurveDarks,
            CurveShadows: overrides.CurveShadows,
            Density: basis.Density + overrides.Density,
            Highlight: basis.Highlight + overrides.Highlight,
            Shadow: basis.Shadow + overrides.Shadow,
            Whites: basis.Whites + overrides.Whites,
            Blacks: basis.Blacks + overrides.Blacks);
    }

    /// <summary>
    /// 질감 세 축은 큰 쪽을 씁니다. clarity 와 vignette 는 프리셋이 정하지 않으므로 더하기가
    /// 아니라 사용자 값 그대로입니다 — macOS 도 프리셋 기본값이 0 이라 더해도 같습니다.
    /// </summary>
    public static TextureRecipe Compose(LookPreset preset, TextureRecipe overrides)
    {
        ArgumentNullException.ThrowIfNull(preset);
        ArgumentNullException.ThrowIfNull(overrides);
        return new TextureRecipe(
            Grain: Math.Max(preset.Texture.Grain, overrides.Grain),
            Sharpness: Math.Max(preset.Texture.Sharpness, overrides.Sharpness),
            Halation: Math.Max(preset.Texture.Halation, overrides.Halation),
            Clarity: overrides.Clarity,
            Vignette: overrides.Vignette);
    }

    /// <summary>
    /// 프리셋 색 축을 사용자 ColorModel 위에 더합니다. vibrance 와 primary 세 축은 프리셋이
    /// 정하지 않으므로 사용자 값이 그대로 남습니다.
    /// </summary>
    public static ColorModelRecipe Compose(LookPreset preset, ColorModelRecipe overrides)
    {
        ArgumentNullException.ThrowIfNull(preset);
        ArgumentNullException.ThrowIfNull(overrides);
        return overrides with
        {
            Warmth = preset.Color.Warmth + overrides.Warmth,
            Tint = preset.Color.Tint + overrides.Tint,
            ColorDepth = preset.Color.ColorDepth + overrides.ColorDepth,
            Saturation = preset.Color.Saturation + overrides.Saturation,
        };
    }
}
