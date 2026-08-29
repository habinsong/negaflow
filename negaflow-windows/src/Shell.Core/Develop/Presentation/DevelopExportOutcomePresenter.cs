using System.Globalization;
using Negaflow.Interop;

namespace Negaflow.Shell.Develop;

/// <summary>Formats stable user-facing export outcomes without owning panel state.</summary>
internal static class DevelopExportOutcomePresenter
{
    public static string Describe(DevelopExportOutcome outcome)
    {
        ArgumentNullException.ThrowIfNull(outcome);
        switch (outcome.Kind)
        {
            case DevelopExportOutcomeKind.Completed when outcome.Result is { } result:
                if (!result.Succeeded)
                {
                    return $"Develop stopped at {Humanize(result.FailedStage)}: {result.FailureName}";
                }
                double milliseconds = result.WallMicroseconds / 1000.0;
                return string.Create(
                    CultureInfo.CurrentCulture,
                    $"Exported {result.ImageWidth}×{result.ImageHeight} in {milliseconds:F0} ms");

            case DevelopExportOutcomeKind.Refused:
                return outcome.Refusal switch
                {
                    DevelopRequestRefusal.MissingManualBase =>
                        "Set the film base (Dmin) before developing this frame.",
                    DevelopRequestRefusal.MissingFilmStock =>
                        "Select a film stock before developing this frame.",
                    DevelopRequestRefusal.UnsupportedBaseEstimationMode =>
                        "This film-base mode is not supported by the Windows engine yet.",
                    DevelopRequestRefusal.UnsupportedDigitalSource =>
                        "This frame is a rendered digital source, which cannot be developed yet.",
                    DevelopRequestRefusal.UnsupportedPositiveFilm =>
                        "Positive film development is not supported by the Windows engine yet.",
                    DevelopRequestRefusal.InvalidDestination =>
                        "Choose a full path to export to.",
                    DevelopRequestRefusal.UnknownOutputFormat =>
                        "That export format is not supported.",
                    DevelopRequestRefusal.StaleDefectSource =>
                        "The scan file changed size since the defect edits were recorded. " +
                        "Relink the frame to the original scan, or clear the defect edits, " +
                        "then export again.",
                    _ => "The develop request was refused.",
                };

            case DevelopExportOutcomeKind.Faulted:
                return $"The engine failed: {outcome.FaultMessage}";

            case DevelopExportOutcomeKind.Busy:
                return "A develop is already running.";

            default:
                return "The develop produced no result.";
        }
    }

    private static string Humanize(DevelopExportStage stage) => stage switch
    {
        DevelopExportStage.RequestValidation => "request validation",
        DevelopExportStage.ObserveSourceBefore => "reading the source file",
        DevelopExportStage.Decode => "decoding",
        DevelopExportStage.ObserveSourceAfter => "re-checking the source file",
        DevelopExportStage.FilmLookWorkspace => "preparing the Film Look",
        DevelopExportStage.Develop => "developing",
        DevelopExportStage.ToneAdjust => "tone adjustment",
        DevelopExportStage.FilmLook => "the Film Look",
        DevelopExportStage.Output => "writing the file",
        _ => "an unknown stage",
    };
}
