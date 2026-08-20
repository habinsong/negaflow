using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using static Negaflow.Shell.UnitTests.TestAssert;

namespace Negaflow.Shell.UnitTests;

/// <summary>macOS <c>selectedBeforeID</c> · <c>compareLabels</c> · <c>beforeImage</c>.</summary>
internal static class CanvasCompareBeforeTests
{
    public static void Run()
    {
        Check(CanvasCompareBeforePolicy.BeforeCenterOffsetX == 60, "before_label_dx_60");
        Check(CanvasCompareBeforePolicy.BeforeCenterOffsetY == 48, "before_label_dy_48");
        Check(CanvasCompareBeforePolicy.AfterVerticalInsetX == 38, "after_label_v_inset_38");
        Check(CanvasCompareBeforePolicy.AfterHorizontalOffsetX == 36, "after_label_h_dx_36");
        Check(CanvasCompareBeforePolicy.MaxWidth == 112, "before_label_max_112");
        Check(CanvasCompareBeforePolicy.CanonicalId(null) == "unedited", "canonical_null_unedited");
        Check(CanvasCompareBeforePolicy.CanonicalId("raw") == "raw", "canonical_raw");
        Check(CanvasCompareBeforePolicy.CanonicalId("frame:missing") == "unedited", "canonical_missing_frame");
        Check(
            CanvasCompareBeforePolicy.CanonicalId("frame:abc", id => id == "abc") == "frame:abc",
            "canonical_existing_frame");

        (double bx, double by) = CanvasCompareBeforePolicy.BeforeCenter(10, 20);
        Check(bx == 70 && by == 68, "before_center");
        (double ax, double ay) = CanvasCompareBeforePolicy.AfterCenter(
            10, 20, 400, 300, CanvasCompareOrientation.Vertical);
        Check(ax == 372 && ay == 68, "after_center_vertical");
        (ax, ay) = CanvasCompareBeforePolicy.AfterCenter(
            10, 20, 400, 300, CanvasCompareOrientation.Horizontal);
        Check(ax == 46 && ay == 302, "after_center_horizontal");

        IReadOnlyList<CanvasCompareBeforeOption> primary = CanvasCompareBeforePolicy.PrimaryOptions(
            "MAIN",
            "Unedited",
            "Raw");
        Check(primary.Count == 3 && primary[0].Id == "main" && primary[2].Id == "raw", "primary_three");
        IReadOnlyList<CanvasCompareBeforeOption> frames = CanvasCompareBeforePolicy.FrameOptions(
            "here",
            [("here", "Current", false), ("other", "Other", true)]);
        Check(frames.Count == 1 && frames[0].Id == "frame:other" && frames[0].IsVirtualCopy,
            "frame_options_skip_current");
        Check(
            CanvasCompareBeforePolicy.BeforeLabel("unedited", primary, frames, "Unedited") == "Unedited",
            "before_label_unedited");
        Check(
            CanvasCompareBeforePolicy.BeforeLabel("frame:other", primary, frames, "Unedited") == "Other",
            "before_label_frame");

        LibraryFrameSnapshot frame = TestFrameFactory.Frame(manualBase: null);
        Check(frame.Tone.Exposure != 0, "fixture_has_tone");
        LibraryFrameSnapshot unedited = CanvasCompareBeforePolicy.BeforeSnapshot(frame, "unedited");
        Check(unedited.Tone.Exposure == 0, "unedited_snapshot_strips_tone");
        Check(
            CanvasCompareBeforePolicy.BeforeSnapshot(frame, "raw").Tone.Exposure == frame.Tone.Exposure,
            "raw_snapshot_keeps_tone");
        Check(
            CanvasCompareBeforePolicy.BeforeUsesUninvertedSource("raw") &&
            !CanvasCompareBeforePolicy.BeforeUsesUninvertedSource("unedited"),
            "raw_uses_uninverted_flag");

        LibraryFrameSnapshot noritsu = frame with { DevelopTarget = DevelopTarget.Noritsu };
        LibraryFrameSnapshot main = CanvasCompareBeforePolicy.BeforeSnapshot(noritsu, "main");
        Check(main.DevelopTarget == DevelopTarget.Main, "main_snapshot_switches_target");
        Check(main.Tone.Exposure == noritsu.Tone.Exposure, "main_snapshot_keeps_adjustments");

        LibraryFrameSnapshot other = TestFrameFactory.Frame(manualBase: null) with { Id = "other" };
        LibraryFrameSnapshot fromFrame = CanvasCompareBeforePolicy.BeforeSnapshot(
            frame,
            "frame:other",
            new Dictionary<string, LibraryFrameSnapshot> { ["other"] = other });
        Check(fromFrame.Id == "other", "frame_snapshot_uses_other");

        CanvasCompareState state = new();
        Check(state.SelectedBeforeId == "unedited", "state_starts_unedited");
        state.SelectBefore("raw");
        Check(state.BeforeContent == CompareBeforeContent.Raw && state.SelectedBeforeId == "raw",
            "state_select_raw");
        state.SelectBefore("frame:gone");
        Check(state.SelectedBeforeId == "unedited", "state_invalid_frame_falls_back");
        state.SelectBefore("frame:ok", id => id == "ok");
        Check(state.BeforeFrameId == "ok" && state.SelectedBeforeId == "frame:ok", "state_select_frame");
    }
}
