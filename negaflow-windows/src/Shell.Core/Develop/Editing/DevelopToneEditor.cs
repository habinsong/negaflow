using Negaflow.Catalog;
using Negaflow.Interop;

namespace Negaflow.Shell.Develop;

/// <summary>Clamps, computes, and persists automatic and manual tone edits.</summary>
internal sealed class DevelopToneEditor
{
    private readonly LibraryHostService host;
    private readonly ToneLimits limits;

    public DevelopToneEditor(LibraryHostService host, ToneLimits limits)
    {
        ArgumentNullException.ThrowIfNull(host);
        ArgumentNullException.ThrowIfNull(limits);
        this.host = host;
        this.limits = limits;
    }

    public double MaximumExposureStops => limits.MaximumExposureStops;

    public double MaximumToneControl => limits.MaximumToneControl;

    public DevelopEditResult ApplyAutoTone(
        LibraryFrameSnapshot? frame,
        AutoAdjustSettings settings)
    {
        ArgumentNullException.ThrowIfNull(settings);
        return frame is null
            ? new(LibraryFrameError.MissingId, false)
            : ApplyAutoAdjusted(AutoAdjustCoordinator.ApplyTone(frame, settings));
    }

    public DevelopEditResult ApplyAutoWhiteBalance(
        LibraryFrameSnapshot? frame,
        AutoAdjustSettings settings)
    {
        ArgumentNullException.ThrowIfNull(settings);
        return frame is null
            ? new(LibraryFrameError.MissingId, false)
            : ApplyAutoAdjusted(AutoAdjustCoordinator.ApplyWhiteBalance(frame, settings));
    }

    public DevelopEditResult SetExposure(LibraryFrameSnapshot? frame, double stops) =>
        SetTone(frame, tone => tone with { Exposure = limits.ClampExposure(stops) });

    public DevelopEditResult SetContrast(LibraryFrameSnapshot? frame, double value) =>
        SetTone(frame, tone => tone with { Contrast = limits.ClampToneControl(value) });

    public DevelopEditResult SetHighlights(LibraryFrameSnapshot? frame, double value) =>
        SetTone(frame, tone => tone with { Highlight = limits.ClampToneControl(value) });

    public DevelopEditResult SetShadows(LibraryFrameSnapshot? frame, double value) =>
        SetTone(frame, tone => tone with { Shadow = limits.ClampToneControl(value) });

    public DevelopEditResult SetWhites(LibraryFrameSnapshot? frame, double value) =>
        SetTone(frame, tone => tone with { Whites = limits.ClampToneControl(value) });

    public DevelopEditResult SetBlacks(LibraryFrameSnapshot? frame, double value) =>
        SetTone(frame, tone => tone with { Blacks = limits.ClampToneControl(value) });

    public DevelopEditResult SetDensity(LibraryFrameSnapshot? frame, double value) =>
        SetTone(frame, tone => tone with { Density = limits.ClampToneControl(value) });

    public DevelopEditResult SetCurveHighlights(LibraryFrameSnapshot? frame, double value) =>
        SetTone(frame, tone => tone with { CurveHighlights = limits.ClampToneControl(value) });

    public DevelopEditResult SetCurveLights(LibraryFrameSnapshot? frame, double value) =>
        SetTone(frame, tone => tone with { CurveLights = limits.ClampToneControl(value) });

    public DevelopEditResult SetCurveDarks(LibraryFrameSnapshot? frame, double value) =>
        SetTone(frame, tone => tone with { CurveDarks = limits.ClampToneControl(value) });

    public DevelopEditResult SetCurveShadows(LibraryFrameSnapshot? frame, double value) =>
        SetTone(frame, tone => tone with { CurveShadows = limits.ClampToneControl(value) });

    public DevelopEditResult ResetBasicTone(LibraryFrameSnapshot? frame) =>
        SetTone(frame, tone => tone with
        {
            Exposure = 0,
            Contrast = 0,
            Density = 0,
            Highlight = 0,
            Shadow = 0,
            Whites = 0,
            Blacks = 0,
        });

    public DevelopEditResult ResetToneCurve(LibraryFrameSnapshot? frame)
    {
        if (frame is null)
        {
            return new(LibraryFrameError.MissingId, false);
        }

        ToneAdjustment tone = frame.Tone with
        {
            CurveHighlights = 0,
            CurveLights = 0,
            CurveDarks = 0,
            CurveShadows = 0,
        };
        return Edit(
            frame,
            new LibraryFrameEdit(
                tone,
                frame.ManualBase,
                PointCurves: PointCurveRecipe.Identity));
    }

    private DevelopEditResult ApplyAutoAdjusted(LibraryFrameSnapshot adjusted) =>
        Edit(
            adjusted,
            new LibraryFrameEdit(
                adjusted.Tone,
                adjusted.ManualBase,
                ColorModel: adjusted.ColorModel));

    private DevelopEditResult SetTone(
        LibraryFrameSnapshot? frame,
        Func<ToneAdjustment, ToneAdjustment> update)
    {
        ArgumentNullException.ThrowIfNull(update);
        if (frame is null)
        {
            return new(LibraryFrameError.MissingId, false);
        }
        return Edit(
            frame,
            new LibraryFrameEdit(update(frame.Tone), frame.ManualBase));
    }

    private DevelopEditResult Edit(LibraryFrameSnapshot frame, LibraryFrameEdit edit)
    {
        LibraryFrameError error = host.Edit(frame.Id, edit);
        return new(error, error == LibraryFrameError.None);
    }
}
