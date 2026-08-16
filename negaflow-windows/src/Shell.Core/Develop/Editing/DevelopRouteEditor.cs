using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

/// <summary>Validates and persists process, film-look, and automatic-correction routing.</summary>
internal sealed class DevelopRouteEditor
{
    private readonly LibraryHostService host;

    public DevelopRouteEditor(LibraryHostService host)
    {
        ArgumentNullException.ThrowIfNull(host);
        this.host = host;
    }

    public static bool ShowsAutoCorrections(LibraryFrameSnapshot? frame) =>
        frame?.Route.FilmType is FilmType.ColorNegative or FilmType.BlackAndWhiteNegative;

    public static bool AppliesFilmLook(LibraryFrameSnapshot? frame) =>
        frame?.Route.IsDigitalSource == true;

    public static DevelopmentProcess DevelopmentProcess(LibraryFrameSnapshot? frame) =>
        frame is null
            ? Catalog.DevelopmentProcess.C41
            : DevelopProcesses.From(frame.Route.FilmType, frame.Route.IsDigitalSource);

    public DevelopEditResult SetAutoLevels(LibraryFrameSnapshot? frame, bool enabled) =>
        SetAutoCorrection(frame, enabled, neutralBalance: null);

    public DevelopEditResult SetAutoNeutralBalance(
        LibraryFrameSnapshot? frame,
        bool enabled) =>
        SetAutoCorrection(frame, autoLevels: null, enabled);

    public DevelopEditResult SetDevelopmentProcess(
        LibraryFrameSnapshot? frame,
        DevelopmentProcess process)
    {
        if (frame is null)
        {
            return Missing();
        }
        if (!Enum.IsDefined(process))
        {
            return new(LibraryFrameError.InvalidDevelopRoute, false);
        }

        DevelopRouteSelection selection = DevelopRouteSelection.FromProcess(
            process,
            frame.Route.FilmEmulation,
            frame.Route.FilmEmulationIntensity);
        LibraryFrameError error = host.EditRoute(frame.Id, selection);
        return new(error, error == LibraryFrameError.None);
    }

    public DevelopEditResult SetFilmEmulation(
        LibraryFrameSnapshot? frame,
        FilmEmulation emulation) =>
        SetFilmLook(frame, emulation, intensity: null);

    public DevelopEditResult SetFilmEmulationIntensity(
        LibraryFrameSnapshot? frame,
        double intensity) =>
        SetFilmLook(frame, emulation: null, Math.Clamp(intensity, 0.0, 1.0));

    private DevelopEditResult SetFilmLook(
        LibraryFrameSnapshot? frame,
        FilmEmulation? emulation,
        double? intensity)
    {
        if (frame is null)
        {
            return Missing();
        }
        if (!AppliesFilmLook(frame))
        {
            return new(LibraryFrameError.InvalidDevelopRoute, false);
        }

        LibraryFrameError error = host.EditRoute(
            frame.Id,
            new DevelopRouteSelection(
                frame.Route.SourceSignalKind,
                frame.Route.FilmType,
                emulation ?? frame.Route.FilmEmulation,
                intensity ?? frame.Route.FilmEmulationIntensity));
        return new(error, error == LibraryFrameError.None);
    }

    private DevelopEditResult SetAutoCorrection(
        LibraryFrameSnapshot? frame,
        bool? autoLevels,
        bool? neutralBalance)
    {
        if (frame is null)
        {
            return Missing();
        }
        if (!ShowsAutoCorrections(frame))
        {
            return new(LibraryFrameError.InvalidDevelopRoute, false);
        }

        LibraryFrameError error = host.Edit(
            frame.Id,
            new LibraryFrameEdit(
                frame.Tone,
                frame.ManualBase,
                AutoLevels: autoLevels ?? frame.AutoLevels,
                AutoNeutralBalance: neutralBalance ?? frame.AutoNeutralBalance));
        return new(error, error == LibraryFrameError.None);
    }

    private static DevelopEditResult Missing() =>
        new(LibraryFrameError.MissingId, false);
}
