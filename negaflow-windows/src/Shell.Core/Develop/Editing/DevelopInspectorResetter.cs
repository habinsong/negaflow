using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

/// <summary>
/// macOS <c>DevelopInspectorResetter</c>. 모든 보정 초기화는 슬라이더·룩과 크롭·수평 각도를
/// 되돌립니다(라이트룸 초기화와 같습니다 — 크롭이 남으면 초기화 뒤에도 크롭 바깥 띠로 베이스를
/// 재는 등 결과가 초기 상태와 달랐습니다, 2026-10-15). 베이스와 필름 방향(90° 회전·뒤집기)은 둡니다.
/// </summary>
internal static class DevelopInspectorResetter
{
    /// <summary>
    /// macOS <c>DevelopWorkflowInspector.neutralPreset</c> —
    /// <c>model.presets.first(where: { $0.id == "neutral" })</c>. 프로파일이 안 읽혔으면
    /// macOS 와 같이 null 이고, 그때는 프리셋 없이 사용자 값만 남습니다.
    /// </summary>
    public static string? NeutralPresetId => LookPresetLibrary.Resolve("neutral")?.Id;

    /// <summary>macOS <c>resetAllAdjustments(frame:neutralPreset:)</c>.</summary>
    public static LibraryFrameEdit ResetAllAdjustments(
        LibraryFrameSnapshot frame,
        string? neutralPresetId)
    {
        ArgumentNullException.ThrowIfNull(frame);
        return new LibraryFrameEdit(
            ToneAdjustment.Neutral,
            frame.InputGamma.IsAutomatic ? frame.ManualBase : null,
            Base: frame.Base with { Scale = 1.0, Mode = !frame.InputGamma.IsAutomatic && frame.Base.Mode == BaseEstimationMode.Manual
                ? BaseEstimationMode.Auto : frame.Base.Mode },
            PointCurves: PointCurveRecipe.Identity,
            ColorMixer: ColorMixerRecipe.Identity,
            ColorGrading: ColorGradingRecipe.Identity,
            PrimaryCalibration: PrimaryCalibrationRecipe.Identity,
            LocalDodgeBurn: [],
            ColorModel: ColorModelRecipe.Identity,
            Texture: TextureRecipe.Identity,
            NoiseReduction: NoiseReductionRecipe.Identity,
            BwToning: BwToningRecipe.None,
            LookPreset: new LookPresetSelection(neutralPresetId),
            ImageTransform: frame.ImageTransform with { Crop = null, CropAspect = null, StraightenAngle = 0.0 })
        { InputGamma = InputGammaInterpretation.Automatic };
    }
}
