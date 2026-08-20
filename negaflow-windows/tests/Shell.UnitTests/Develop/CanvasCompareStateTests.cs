using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using static Negaflow.Shell.UnitTests.TestAssert;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// macOS <c>selectCompareMode</c> · <c>toggleDevelopedShortcut</c> · <c>activeCompareMode</c>.
/// 신쇄 <see cref="CanvasCompareState"/>.
/// </summary>
internal static class CanvasCompareStateTests
{
    public static void Run()
    {
        CanvasCompareState state = new();
        Check(state.ActiveMode == CanvasCompareMode.Developed, "compare_starts_developed");
        Check(state.ShowDeveloped, "compare_starts_showing_developed");
        Check(state.PreviousMode == CanvasCompareMode.Raw, "compare_previous_starts_raw");
        Check(state.BeforeContent == CompareBeforeContent.Unedited, "compare_before_starts_unedited");

        state.Select(CanvasCompareMode.Raw);
        Check(state.ActiveMode == CanvasCompareMode.Raw, "select_raw_active");
        Check(!state.ShowDeveloped, "select_raw_hides_developed");
        Check(state.PreviousMode == CanvasCompareMode.Raw, "select_raw_remembers_previous");
        Check(!state.BeforeAfterCompareActive, "raw_is_not_split");

        state.CanCompare = true;
        state.Select(CanvasCompareMode.SplitVertical);
        Check(state.ActiveMode == CanvasCompareMode.SplitVertical, "select_split_v");
        Check(state.ShowDeveloped, "split_shows_developed");
        Check(state.PreviousMode == CanvasCompareMode.SplitVertical, "split_becomes_previous");
        Check(state.IsComparingSplit && state.BeforeAfterCompareActive, "split_gates_compare");

        state.DevelopTarget = DevelopTarget.Noritsu;
        state.SelectBefore(CanvasCompareBeforePolicy.MainId);
        state.UpdateCompareGating();
        Check(state.BeforeAfterMainCompareActive, "split_main_before_on_noritsu");

        state.Select(CanvasCompareMode.Developed);
        Check(state.ActiveMode == CanvasCompareMode.Developed, "select_developed");
        Check(state.PreviousMode == CanvasCompareMode.SplitVertical, "developed_keeps_split_previous");
        Check(!state.BeforeAfterCompareActive, "developed_clears_split_gate");

        state.ToggleDeveloped();
        Check(state.ActiveMode == CanvasCompareMode.SplitVertical, "toggle_from_developed_restores_previous");

        state.ToggleDeveloped();
        Check(state.ActiveMode == CanvasCompareMode.Developed, "toggle_from_split_returns_developed");

        state.CanCompare = false;
        state.Select(CanvasCompareMode.SplitHorizontal);
        Check(
            state.ActiveMode == CanvasCompareMode.Developed,
            "no_before_image_collapses_split_to_developed");
        Check(!state.IsComparingSplit, "collapsed_split_is_not_comparing");

        RunPerFrame();
    }

    /// <summary>
    /// macOS <c>ScanFrame.showDeveloped</c> 는 프레임마다 따로 삽니다. 한 프레임에서 켠
    /// `원본` 이 다음 프레임까지 따라가면 그 프레임도 반전 전 네거티브로 그려집니다.
    /// </summary>
    private static void RunPerFrame()
    {
        CanvasCompareState state = new();
        state.BindFrame("frame-a");
        Check(state.ActiveMode == CanvasCompareMode.Developed, "bound_frame_starts_developed");

        state.Select(CanvasCompareMode.Raw);
        Check(state.ActiveMode == CanvasCompareMode.Raw, "frame_a_is_raw");

        state.BindFrame("frame-b");
        Check(
            state.ActiveMode == CanvasCompareMode.Developed,
            "new_frame_starts_developed_not_raw");
        Check(state.ShowDeveloped, "new_frame_shows_developed");

        state.BindFrame("frame-a");
        Check(state.ActiveMode == CanvasCompareMode.Raw, "returning_frame_restores_its_raw");

        state.BindFrame(null);
        Check(state.ActiveMode == CanvasCompareMode.Developed, "no_frame_falls_back_to_developed");
    }
}
