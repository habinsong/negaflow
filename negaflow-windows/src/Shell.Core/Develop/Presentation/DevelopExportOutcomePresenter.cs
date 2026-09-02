using System.Globalization;
using Negaflow.Interop;

namespace Negaflow.Shell.Develop;

/// <summary>
/// 현상·내보내기 결과를 <b>기록용 한 줄</b>로 적습니다.
/// </summary>
/// <remarks>
/// 이 글자는 <c>export-trace.txt</c> 같은 기록에만 들어갑니다. 기록은 어느 언어로 앱을 켰든
/// 같은 글자여야 읽고 비교할 수 있으므로 번역하지 않습니다 — <b>화면에 적는 문구는
/// <c>Shell/Localization/DevelopExportOutcomeText.cs</c> 가 만듭니다.</b>
/// </remarks>
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
                    DevelopRequestRefusal.NoFrameSelected =>
                        "Select a photo first.",
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
