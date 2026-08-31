using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using static Negaflow.Shell.UnitTests.TestAssert;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 붓 오버레이가 <b>포인터가 있던 자리</b>에 칠하는지 고정합니다.
/// </summary>
/// <remarks>
/// 이 표면이 그리는 획은 아직 recipe 로 가지 않은 것이고, 좌표는 포인터가 준
/// <b>표시 정규 좌표</b> 그대로입니다. 앞 판은 이것을 <c>DefectDisplayLocator</c>(원본→표시)
/// 에 통과시켜 변환이 두 번 걸렸고, 크롭·회전·뒤집기를 한 사진에서 <b>편집 전 자리</b>에
/// 칠해졌습니다(2026-08-31 보고). 크롭도 회전도 없으면 항등이라 드러나지 않았습니다.
///
/// macOS <c>BrushOverlay</c> 도 <c>canvasPoint(fromUnit:)</c> 로 표시 단위를 그대로 씁니다.
/// </remarks>
internal static class GrainMendPaintOverlayTests
{
    private const int Width = 101;
    private const int Height = 101;

    public static void Run()
    {
        InProgressStrokePaintsAtThePointerPosition();
        PaintedStrokePaintsAtThePointerPosition();
        NothingToPaintLeavesTheSurfaceEmpty();
    }

    private static void InProgressStrokePaintsAtThePointerPosition()
    {
        // 표시 정규 (0.75, 0.25) 한 점. 그 자리가 칠해져야 합니다.
        byte[]? bgra = GrainMendPaintOverlayRenderer.Render(
            Width,
            Height,
            [],
            [new DefectPoint(0.75, 0.25)],
            0.02);

        Check(bgra is not null, "brush_overlay_renders");
        if (bgra is null)
        {
            return;
        }
        Check(IsPainted(bgra, 0.75, 0.25), "brush_overlay_paints_at_the_pointer_position");
        // 반대쪽 구석은 손대지 않아야 합니다 — 변환이 한 번 더 걸리면 여기로 새어 나갑니다.
        Check(!IsPainted(bgra, 0.25, 0.75), "brush_overlay_does_not_paint_the_mirrored_spot");
    }

    private static void PaintedStrokePaintsAtThePointerPosition()
    {
        // 확정된(그러나 아직 적용하지 않은) 획도 같은 공간입니다.
        byte[]? bgra = GrainMendPaintOverlayRenderer.Render(
            Width,
            Height,
            [new DefectStroke([new DefectPoint(0.1, 0.9)], 0.02)],
            [],
            0.02);

        Check(bgra is not null, "brush_overlay_renders_painted_strokes");
        if (bgra is null)
        {
            return;
        }
        Check(IsPainted(bgra, 0.1, 0.9), "painted_stroke_stays_where_it_was_painted");
        Check(!IsPainted(bgra, 0.9, 0.1), "painted_stroke_does_not_move_to_the_mirrored_spot");
    }

    private static void NothingToPaintLeavesTheSurfaceEmpty() =>
        Check(
            GrainMendPaintOverlayRenderer.Render(Width, Height, [], [], 0.02) is null,
            "brush_overlay_is_absent_without_strokes");

    /// <summary>표시 정규 좌표 한 점이 실제로 칠해졌는지 봅니다.</summary>
    private static bool IsPainted(byte[] bgra, double unitX, double unitY)
    {
        int x = (int)Math.Round(unitX * (Width - 1));
        int y = (int)Math.Round(unitY * (Height - 1));
        return bgra[(((y * Width) + x) * 4) + 3] > 0;
    }
}
