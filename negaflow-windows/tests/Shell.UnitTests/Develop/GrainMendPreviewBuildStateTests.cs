using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using static Negaflow.Shell.UnitTests.TestAssert;
using static Negaflow.Shell.UnitTests.TestFrameFactory;

namespace Negaflow.Shell.UnitTests;

internal static class GrainMendPreviewBuildStateTests
{
    public static void Run()
    {
        GrainMendPreviewBuildState state = new();
        LibraryFrameSnapshot revision2 = Snapshot("frame-a", 2UL);
        LibraryFrameSnapshot revision3 = Snapshot("frame-a", 3UL);

        state.Begin(revision2);
        Check(state.IsBusy, "grain_mend_preview_build_starts_busy");
        Check(!state.Complete(Snapshot("frame-b", 2UL)) && state.IsBusy,
            "grain_mend_preview_build_ignores_other_frame");
        Check(!state.Complete(Snapshot("frame-a", 1UL)) && state.IsBusy,
            "grain_mend_preview_build_ignores_old_revision");

        state.Begin(revision3);
        Check(!state.Complete(revision2) && state.IsBusy,
            "grain_mend_preview_build_new_revision_supersedes_old");
        Check(state.Complete(revision3) && !state.IsBusy,
            "grain_mend_preview_build_matching_preview_completes");

        state.Begin(revision3);
        state.Reset();
        Check(!state.IsBusy && !state.Complete(revision3),
            "grain_mend_preview_build_frame_change_resets");
    }

    private static LibraryFrameSnapshot Snapshot(string id, ulong revision) =>
        Frame(new ManualBaseRgb(0.2, 0.2, 0.2)) with
        {
            Id = id,
            DefectRecipeRevision = revision,
        };
}
