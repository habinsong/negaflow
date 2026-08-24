using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

/// <summary>macOS <c>runInfraredCleanIfNeeded</c> 게이트.</summary>
public static class InfraredCleanPolicy
{
    /// <summary>
    /// macOS 기준은 400 ms입니다. Windows는 같은 마지막 선택·취소 계약과 화소 처리를
    /// 유지하면서 실측 IR 선택 p95의 고정 대기만 50 ms 줄입니다.
    /// </summary>
    public const int SelectionDebounceMilliseconds = 350;

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
        status == InfraredDefectApplyStatus.Cancelled;
}
