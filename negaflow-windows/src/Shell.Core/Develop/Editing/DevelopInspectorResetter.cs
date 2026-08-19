using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

/// <summary>
/// macOS <c>DevelopInspectorResetter</c>. 모든 보정 초기화는 슬라이더·룩만 되돌리고
/// 베이스와 기하(<c>imageTransform</c>)는 건드리지 않습니다.
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
            frame.ManualBase,
            PointCurves: PointCurveRecipe.Identity,
            ColorMixer: ColorMixerRecipe.Identity,
            ColorGrading: ColorGradingRecipe.Identity,
            PrimaryCalibration: PrimaryCalibrationRecipe.Identity,
            LocalDodgeBurn: [],
            ColorModel: ColorModelRecipe.Identity,
            Texture: TextureRecipe.Identity,
            NoiseReduction: NoiseReductionRecipe.Identity,
            BwToning: BwToningRecipe.None,
            LookPreset: new LookPresetSelection(neutralPresetId));
    }
}
