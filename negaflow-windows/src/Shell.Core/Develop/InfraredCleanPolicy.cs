using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

/// <summary>macOS <c>runInfraredCleanIfNeeded</c> 게이트.</summary>
public static class InfraredCleanPolicy
{
    /// <summary>macOS <c>infraredSelectionDebounceNanoseconds</c> = 400 ms.</summary>
    public const int SelectionDebounceMilliseconds = 400;

    public static bool ShouldRun(
        LibraryFrameSnapshot? frame,
        bool alreadyAttempted)
    {
        if (frame is null || alreadyAttempted)
        {
            return false;
        }

        if (string.IsNullOrEmpty(frame.InfraredPath) ||
            string.IsNullOrEmpty(frame.SourcePath))
        {
            return false;
        }

        if (frame.DefectRecipe?.Items.Any(item => item.Kind == DefectEditKind.Infrared) == true)
        {
            return false;
        }

        return InfraredFilmCompatibilityRules.AllowsAutomaticCorrection(frame.Route.FilmType);
    }

    public static bool ShouldRearm(InfraredDefectApplyStatus status) =>
        status is InfraredDefectApplyStatus.Cancelled
            or InfraredDefectApplyStatus.DetectionFailed
            or InfraredDefectApplyStatus.SourceMismatch
            or InfraredDefectApplyStatus.PersistenceFailed;
}
