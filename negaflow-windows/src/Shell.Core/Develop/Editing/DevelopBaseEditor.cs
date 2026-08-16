using Negaflow.Catalog;
using Negaflow.Interop;

namespace Negaflow.Shell.Develop;

/// <summary>Validates and persists the film-base recipe for one frame.</summary>
internal sealed class DevelopBaseEditor
{
    private readonly LibraryHostService host;
    private readonly NegativeLimits limits;

    public DevelopBaseEditor(LibraryHostService host, NegativeLimits limits)
    {
        ArgumentNullException.ThrowIfNull(host);
        ArgumentNullException.ThrowIfNull(limits);
        this.host = host;
        this.limits = limits;
    }

    public double MinimumManualDmin => limits.MinimumManualDmin;

    public double MaximumManualDmin => limits.MaximumManualDmin;

    public double SuggestedManualDmin =>
        limits.ClampChannel((MinimumManualDmin + MaximumManualDmin) / 4.0);

    public static bool CanEdit(LibraryFrameSnapshot? frame) =>
        frame?.Route.FilmType is FilmType.ColorNegative or FilmType.BlackAndWhiteNegative;

    public DevelopEditResult SetMode(LibraryFrameSnapshot? frame, BaseEstimationMode mode)
    {
        if (frame is null)
        {
            return new(LibraryFrameError.MissingId, false);
        }
        if (mode is not (BaseEstimationMode.Auto or BaseEstimationMode.Preset or
            BaseEstimationMode.Manual))
        {
            return new(LibraryFrameError.InvalidBaseRecipe, false);
        }
        if (!CanEdit(frame))
        {
            return new(LibraryFrameError.InvalidDevelopRoute, false);
        }

        ManualBaseRgb? manualBase = frame.ManualBase;
        if (mode == BaseEstimationMode.Manual && manualBase is null)
        {
            manualBase = new ManualBaseRgb(
                limits.ClampChannel(0.90),
                limits.ClampChannel(0.65),
                limits.ClampChannel(0.45));
        }
        return Edit(
            frame,
            new LibraryFrameEdit(frame.Tone, manualBase, frame.Base with { Mode = mode }));
    }

    public DevelopEditResult SetFilmStock(LibraryFrameSnapshot? frame, string? filmStockDminId)
    {
        if (frame is null)
        {
            return new(LibraryFrameError.MissingId, false);
        }
        if (!CanEdit(frame))
        {
            return new(LibraryFrameError.InvalidDevelopRoute, false);
        }
        if (!BundledFilmBaseOptions.IsKnownFilmStock(filmStockDminId))
        {
            return new(LibraryFrameError.InvalidBaseRecipe, false);
        }

        BaseRecipe updated = frame.Base with
        {
            Mode = filmStockDminId is null ? BaseEstimationMode.Auto : BaseEstimationMode.Preset,
            FilmStockDminId = filmStockDminId,
        };
        return Edit(frame, new LibraryFrameEdit(frame.Tone, frame.ManualBase, updated));
    }

    public DevelopEditResult SetLightSource(
        LibraryFrameSnapshot? frame,
        string? lightSourceProfileId)
    {
        if (frame is null)
        {
            return new(LibraryFrameError.MissingId, false);
        }
        if (!CanEdit(frame))
        {
            return new(LibraryFrameError.InvalidDevelopRoute, false);
        }
        if (frame.Base.Mode != BaseEstimationMode.Preset ||
            !BundledFilmBaseOptions.IsKnownLightSource(lightSourceProfileId))
        {
            return new(LibraryFrameError.InvalidBaseRecipe, false);
        }
        return Edit(
            frame,
            new LibraryFrameEdit(
                frame.Tone,
                frame.ManualBase,
                frame.Base with { LightSourceProfileId = lightSourceProfileId }));
    }

    public DevelopEditResult SetScannerProfile(
        LibraryFrameSnapshot? frame,
        string? scannerProfileId)
    {
        if (frame is null)
        {
            return new(LibraryFrameError.MissingId, false);
        }
        if (!CanEdit(frame))
        {
            return new(LibraryFrameError.InvalidDevelopRoute, false);
        }
        if (frame.Base.Mode != BaseEstimationMode.Preset ||
            !BundledFilmBaseOptions.IsKnownScannerProfile(scannerProfileId))
        {
            return new(LibraryFrameError.InvalidBaseRecipe, false);
        }
        return Edit(
            frame,
            new LibraryFrameEdit(
                frame.Tone,
                frame.ManualBase,
                frame.Base with { ScannerProfileId = scannerProfileId }));
    }

    public DevelopEditResult SetManualBase(
        LibraryFrameSnapshot? frame,
        double red,
        double green,
        double blue)
    {
        if (frame is null)
        {
            return new(LibraryFrameError.MissingId, false);
        }
        if (!CanEdit(frame))
        {
            return new(LibraryFrameError.InvalidDevelopRoute, false);
        }

        ManualBaseRgb clamped = new(
            limits.ClampChannel(red),
            limits.ClampChannel(green),
            limits.ClampChannel(blue));
        return Edit(
            frame,
            new LibraryFrameEdit(
                frame.Tone,
                clamped,
                frame.Base with { Mode = BaseEstimationMode.Manual }));
    }

    private DevelopEditResult Edit(LibraryFrameSnapshot frame, LibraryFrameEdit edit)
    {
        LibraryFrameError error = host.Edit(frame.Id, edit);
        return new(error, error == LibraryFrameError.None);
    }
}
