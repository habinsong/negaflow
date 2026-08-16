using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

/// <summary>Persists color, curve, calibration, and black-and-white toning recipes.</summary>
internal sealed class DevelopColorEditor
{
    private readonly LibraryHostService host;

    public DevelopColorEditor(LibraryHostService host)
    {
        ArgumentNullException.ThrowIfNull(host);
        this.host = host;
    }

    public DevelopEditResult ResetColor(LibraryFrameSnapshot? frame)
    {
        if (frame is null)
        {
            return Missing();
        }
        return Edit(
            frame,
            new LibraryFrameEdit(
                frame.Tone,
                frame.ManualBase,
                ColorModel: frame.ColorModel with
                {
                    Warmth = 0.0,
                    Tint = 0.0,
                    Vibrance = 0.0,
                    Saturation = 0.0,
                    ColorDepth = 0.0,
                }));
    }

    public DevelopEditResult SetPointCurves(
        LibraryFrameSnapshot? frame,
        PointCurveRecipe pointCurves)
    {
        ArgumentNullException.ThrowIfNull(pointCurves);
        return frame is null
            ? Missing()
            : Edit(
                frame,
                new LibraryFrameEdit(frame.Tone, frame.ManualBase, PointCurves: pointCurves));
    }

    public DevelopEditResult SetColorMixer(
        LibraryFrameSnapshot? frame,
        ColorMixerRecipe colorMixer)
    {
        ArgumentNullException.ThrowIfNull(colorMixer);
        return frame is null
            ? Missing()
            : Edit(
                frame,
                new LibraryFrameEdit(frame.Tone, frame.ManualBase, ColorMixer: colorMixer));
    }

    public DevelopEditResult SetColorGrading(
        LibraryFrameSnapshot? frame,
        ColorGradingRecipe colorGrading)
    {
        ArgumentNullException.ThrowIfNull(colorGrading);
        return frame is null
            ? Missing()
            : Edit(
                frame,
                new LibraryFrameEdit(frame.Tone, frame.ManualBase, ColorGrading: colorGrading));
    }

    public DevelopEditResult SetColorModel(
        LibraryFrameSnapshot? frame,
        ColorModelRecipe colorModel)
    {
        ArgumentNullException.ThrowIfNull(colorModel);
        return frame is null
            ? Missing()
            : Edit(
                frame,
                new LibraryFrameEdit(frame.Tone, frame.ManualBase, ColorModel: colorModel));
    }

    public DevelopEditResult SetPrimaryCalibration(
        LibraryFrameSnapshot? frame,
        PrimaryCalibrationRecipe calibration)
    {
        ArgumentNullException.ThrowIfNull(calibration);
        return frame is null
            ? Missing()
            : Edit(
                frame,
                new LibraryFrameEdit(
                    frame.Tone,
                    frame.ManualBase,
                    PrimaryCalibration: calibration));
    }

    public DevelopEditResult SetBwToning(
        LibraryFrameSnapshot? frame,
        BwToningRecipe bwToning) =>
        frame is null
            ? Missing()
            : Edit(
                frame,
                new LibraryFrameEdit(frame.Tone, frame.ManualBase, BwToning: bwToning));

    public DevelopEditResult SetBwToningMode(
        LibraryFrameSnapshot? frame,
        BwToningMode mode)
    {
        if (!Enum.IsDefined(mode))
        {
            return new(LibraryFrameError.InvalidBwToning, false);
        }
        if (frame is null)
        {
            return Missing();
        }
        BwToningRecipe current = frame.BwToning;
        return SetBwToning(
            frame,
            mode == BwToningMode.None
                ? BwToningRecipe.None
                : BwToningRecipe.For(
                    mode,
                    Math.Max(current.ClampedStrength, BwToningRecipe.EngagedStrength)));
    }

    private DevelopEditResult Edit(LibraryFrameSnapshot frame, LibraryFrameEdit edit)
    {
        LibraryFrameError error = host.Edit(frame.Id, edit);
        return new(error, error == LibraryFrameError.None);
    }

    private static DevelopEditResult Missing() =>
        new(LibraryFrameError.MissingId, false);
}
