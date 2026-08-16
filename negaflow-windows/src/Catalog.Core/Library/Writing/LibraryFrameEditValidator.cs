namespace Negaflow.Catalog;

internal static class LibraryFrameEditValidator
{
    internal static LibraryFrameError Validate(LibraryFrameEdit edit)
    {
        if (!ToneRecipeJsonCodec.IsValid(edit.Tone))
        {
            return LibraryFrameError.InvalidToneValue;
        }
        if (!BaseRecipeJsonCodec.IsValid(edit.ManualBase, edit.Base))
        {
            return edit.ManualBase is { } manual && !BaseRecipeJsonCodec.IsValid(manual)
                ? LibraryFrameError.InvalidManualBase
                : LibraryFrameError.InvalidBaseRecipe;
        }
        if (edit.PointCurves is { } pointCurves && !ColorRecipeJsonCodec.IsValid(pointCurves))
        {
            return LibraryFrameError.InvalidPointCurves;
        }
        if (edit.ColorMixer is { } colorMixer && !ColorRecipeJsonCodec.IsValid(colorMixer))
        {
            return LibraryFrameError.InvalidColorMixer;
        }
        if (edit.ColorGrading is { } grading && !ColorRecipeJsonCodec.IsValid(grading))
        {
            return LibraryFrameError.InvalidColorGrading;
        }
        if (edit.PrimaryCalibration is { } calibration && !ColorRecipeJsonCodec.IsValid(calibration))
        {
            return LibraryFrameError.InvalidPrimaryCalibration;
        }
        if (edit.LocalDodgeBurn is { } local && !LocalDodgeBurnJsonCodec.IsValid(local))
        {
            return LibraryFrameError.InvalidLocalDodgeBurn;
        }
        if (edit.ColorModel is { } colorModel && !colorModel.IsValid())
        {
            return LibraryFrameError.InvalidColorModel;
        }
        if (edit.DevelopTarget is { } target && !Enum.IsDefined(target))
        {
            return LibraryFrameError.InvalidDevelopTarget;
        }
        if (edit.ImageTransform is { } transform && !transform.IsValid)
        {
            return LibraryFrameError.InvalidImageTransform;
        }
        if (edit.Texture is { } texture && !texture.IsValid)
        {
            return LibraryFrameError.InvalidTexture;
        }
        if (edit.NoiseReduction is { } noiseReduction && !noiseReduction.IsValid)
        {
            return LibraryFrameError.InvalidNoiseReduction;
        }
        if (edit.BwToning is { } bwToning && !bwToning.IsValid)
        {
            return LibraryFrameError.InvalidBwToning;
        }
        if (edit.DefectRemovalStrength is { } defectRemoval &&
            (!double.IsFinite(defectRemoval) || defectRemoval is < 0.0 or > 1.0))
        {
            return LibraryFrameError.InvalidDefectRecipe;
        }
        if (edit.Rating is { } rating && rating is < 0 or > 5)
        {
            return LibraryFrameError.InvalidRating;
        }
        if (edit.LookPreset is { Id: { } presetId } && string.IsNullOrWhiteSpace(presetId))
        {
            return LibraryFrameError.InvalidLookPresetId;
        }
        return LibraryFrameError.None;
    }
}
