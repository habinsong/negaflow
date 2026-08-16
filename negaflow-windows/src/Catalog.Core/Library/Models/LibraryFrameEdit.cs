namespace Negaflow.Catalog;

public readonly record struct LookPresetSelection(string? Id)
{
    public static LookPresetSelection None => new((string?)null);
}

public readonly record struct DisplayNameSelection(string? Name)
{
    public static DisplayNameSelection None => new((string?)null);

    public static DisplayNameSelection Normalized(string? value)
    {
        string trimmed = (value ?? string.Empty).Trim();
        return new DisplayNameSelection(trimmed.Length == 0 ? null : trimmed);
    }
}

public sealed record LibraryFrameEdit(
    ToneAdjustment Tone,
    ManualBaseRgb? ManualBase,
    BaseRecipe? Base = null,
    PointCurveRecipe? PointCurves = null,
    ColorMixerRecipe? ColorMixer = null,
    ColorGradingRecipe? ColorGrading = null,
    PrimaryCalibrationRecipe? PrimaryCalibration = null,
    IReadOnlyList<LocalDodgeBurnAdjustment>? LocalDodgeBurn = null,
    ColorModelRecipe? ColorModel = null,
    bool? AutoLevels = null,
    bool? AutoNeutralBalance = null,
    DevelopTarget? DevelopTarget = null,
    ImageTransformRecipe? ImageTransform = null,
    TextureRecipe? Texture = null,
    NoiseReductionRecipe? NoiseReduction = null,
    BwToningRecipe? BwToning = null,
    double? DefectRemovalStrength = null,
    int? Rating = null,
    LookPresetSelection? LookPreset = null,
    FramePickState? PickState = null,
    DisplayNameSelection? DisplayName = null);
