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

    /// <summary>
    /// 잰 base 도 수동 값도 없을 때 수동 슬라이더가 서는 자리입니다. macOS
    /// <c>DevelopInspectorBindings</c> 의 <c>SIMD3(0.90, 0.65, 0.45)</c> 이며,
    /// <b>측정값이 있으면 쓰이지 않습니다</b> — 그쪽이 먼저입니다.
    /// </summary>
    public static readonly ManualBaseRgb FallbackManualBase = new(0.90, 0.65, 0.45);

    public static bool CanEdit(LibraryFrameSnapshot? frame) =>
        frame?.Route.FilmType is FilmType.ColorNegative or FilmType.BlackAndWhiteNegative;

    /// <summary>
    /// macOS <c>frame.params.manualBaseRGB ?? frame.baseRGB ?? SIMD3(0.90, 0.65, 0.45)</c>.
    /// </summary>
    public ManualBaseRgb ManualBaseOrMeasured(
        ManualBaseRgb? manualBase,
        ManualBaseRgb? measuredBase) =>
        Clamp(manualBase ?? measuredBase ?? FallbackManualBase);

    private ManualBaseRgb Clamp(ManualBaseRgb rgb) => new(
        limits.ClampChannel(rgb.Red),
        limits.ClampChannel(rgb.Green),
        limits.ClampChannel(rgb.Blue));

    public DevelopEditResult SetMode(
        LibraryFrameSnapshot? frame,
        BaseEstimationMode mode,
        ManualBaseRgb? measuredBase = null)
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
            // macOS `DevelopInspectorBindings.baseMode`:
            //     params.manualBaseRGB = frame.baseRGB ?? SIMD3(0.90, 0.65, 0.45)
            // **자동으로 잰 base 가 먼저입니다.** 앞 판은 그 절반을 빠뜨리고 늘 0.90/0.65/0.45
            // 를 넣어, 자동에서 수동으로 옮기는 순간 방금까지 보고 있던 그림이 딴 것이 됐습니다.
            manualBase = ManualBaseOrMeasured(null, measuredBase);
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

    /// <summary>
    /// macOS <c>resetManualBase</c> — <c>frame.updateParams { $0.manualBaseRGB = nil }</c>.
    /// 값을 <b>지웁니다.</b> 지우면 표시와 현상이 다시 잰 base 를 따라가며, 그것도 없을 때만
    /// <see cref="FallbackManualBase"/> 로 물러납니다.
    /// </summary>
    public DevelopEditResult ClearManualBase(LibraryFrameSnapshot? frame)
    {
        if (frame is null)
        {
            return new(LibraryFrameError.MissingId, false);
        }
        if (!CanEdit(frame))
        {
            return new(LibraryFrameError.InvalidDevelopRoute, false);
        }
        return Edit(frame, new LibraryFrameEdit(frame.Tone, null, frame.Base));
    }

    private DevelopEditResult Edit(LibraryFrameSnapshot frame, LibraryFrameEdit edit)
    {
        LibraryFrameError error = host.Edit(frame.Id, edit);
        return new(error, error == LibraryFrameError.None);
    }
}
