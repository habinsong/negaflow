using Negaflow.Shell.Develop;
using static Negaflow.Shell.UnitTests.TestAssert;

namespace Negaflow.Shell.UnitTests;

/// <summary>macOS <c>CanvasViewportStateTests</c>. 신쇄 <see cref="CanvasViewportState"/>.</summary>
internal static class CanvasViewportStateTests
{
    public static void Run()
    {
        const double imageWidth = 1000;
        const double imageHeight = 800;
        const double canvasWidth = 500;
        const double canvasHeight = 400;

        CanvasViewportState clamp = new();
        clamp.SetScale(40, imageWidth, imageHeight, canvasWidth, canvasHeight);
        Check(clamp.Scale == CanvasViewportState.MaxScale, "viewport_clamps_scale_to_max");
        Check(clamp.LastScale == CanvasViewportState.MaxScale, "viewport_commits_clamped_scale");
        Check(clamp.OffsetX == clamp.LastOffsetX && clamp.OffsetY == clamp.LastOffsetY,
            "viewport_commits_offset_with_scale");
        Check(clamp.ZoomText == "1200%", "viewport_zoom_text_at_max");

        CanvasViewportState pan = new();
        pan.SetScale(2, imageWidth, imageHeight, canvasWidth, canvasHeight);
        pan.UpdatePan(10_000, -10_000, imageWidth, imageHeight, canvasWidth, canvasHeight);
        Check(pan.OffsetX == 266 && pan.OffsetY == -232, "viewport_pan_clamps_to_canvas");
        pan.EndPan();
        Check(pan.LastOffsetX == pan.OffsetX && pan.LastOffsetY == pan.OffsetY, "viewport_end_pan_commits");

        CanvasViewportState magnify = new();
        magnify.SetScale(2, imageWidth, imageHeight, canvasWidth, canvasHeight);
        magnify.UpdateMagnification(1.5, imageWidth, imageHeight, canvasWidth, canvasHeight);
        Check(magnify.Scale == 3, "viewport_magnify_uses_last_scale");
        Check(magnify.LastScale == 2, "viewport_magnify_does_not_commit_until_end");
        magnify.EndMagnification();
        Check(magnify.LastScale == 3, "viewport_end_magnify_commits_scale");
        Check(magnify.LastOffsetX == magnify.OffsetX && magnify.LastOffsetY == magnify.OffsetY,
            "viewport_end_magnify_commits_offset");

        CanvasViewportState hud = new();
        hud.SetScale(2, imageWidth, imageHeight, canvasWidth, canvasHeight);
        hud.ZoomBy(1.25, imageWidth, imageHeight, canvasWidth, canvasHeight);
        Check(hud.Scale == 2.5, "viewport_hud_zoom_in_1_25");
        hud.ZoomBy(1 / 1.25, imageWidth, imageHeight, canvasWidth, canvasHeight);
        Check(hud.Scale == 2, "viewport_hud_zoom_out_1_25");
        hud.Reset();
        Check(hud.Scale == 1 && hud.OffsetX == 0 && hud.OffsetY == 0, "viewport_fit_resets");
        double actual = hud.ActualSizeScale(imageWidth, imageHeight, canvasWidth, canvasHeight);
        hud.SetScale(actual, imageWidth, imageHeight, canvasWidth, canvasHeight);
        Check(hud.Scale == actual && actual > 1, "viewport_actual_size_is_inverse_fit");
    }
}
