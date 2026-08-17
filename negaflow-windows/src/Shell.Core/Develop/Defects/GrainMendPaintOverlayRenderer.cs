using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

/// <summary>
/// 칠하는 동안 보이는 브러시 오버레이입니다. macOS
/// <c>Features/Defects/Brush/BrushOverlay.swift</c> 의 <c>paint</c> 를 그대로 옮긴 것입니다 —
/// 이미 적용된 레이어를 그리는 <see cref="DefectMaskOverlayRenderer"/> 와 다른 표면이고,
/// macOS 도 두 표면이 서로 다른 색·굵기 규칙을 씁니다.
/// </summary>
/// <remarks>
/// macOS 는 확정된 획(<c>strokes</c>)과 진행 중인 획(<c>current</c>)을 같은 캔버스에 같은
/// 규칙으로 칠합니다. 진행 중인 획은 굵기를 지금 슬라이더 값으로 쓰고, 확정된 획은 자기가
/// 칠해질 때의 굵기를 씁니다.
/// </remarks>
public static class GrainMendPaintOverlayRenderer
{
    /// <summary>
    /// 표시 크기 <paramref name="width"/>×<paramref name="height"/> 의 BGRA8 오버레이입니다.
    /// 칠한 것이 없으면 <see langword="null"/> 입니다.
    /// </summary>
    /// <param name="strokes">확정된 획. 각자 자기 굵기를 들고 있습니다.</param>
    /// <param name="inProgress">
    /// 진행 중인 획의 표시 정규 좌표(0~1). 비어 있으면 그리지 않습니다.
    /// </param>
    /// <param name="inProgressThickness">
    /// 진행 중인 획의 굵기(짧은 변에 대한 비율) — macOS 는 지금 슬라이더 값을 씁니다.
    /// </param>
    public static byte[]? Render(
        LibraryFrameSnapshot frame,
        int width,
        int height,
        IReadOnlyList<DefectStroke> strokes,
        IReadOnlyList<DefectPoint> inProgress,
        double inProgressThickness)
    {
        ArgumentNullException.ThrowIfNull(frame);
        ArgumentNullException.ThrowIfNull(strokes);
        ArgumentNullException.ThrowIfNull(inProgress);
        if (width <= 0 || height <= 0 ||
            (strokes.Count == 0 && inProgress.Count == 0) ||
            DefectDisplayLocator.Build(frame, width, height) is not { } locator)
        {
            return null;
        }

        byte[] bgra = new byte[checked(width * height * 4)];
        DefectCanvas canvas = new(bgra, width, height);
        foreach (DefectStroke stroke in strokes)
        {
            Paint(canvas, locator, stroke.Points, stroke.Thickness);
        }
        Paint(canvas, locator, inProgress, inProgressThickness);
        return canvas.Touched ? bgra : null;
    }

    /// <summary>
    /// macOS <c>paint</c>: 굵기는 <c>max(1, thickness × min(imageFrame.width, height))</c>,
    /// 점이 하나면 그 지름의 원, 여럿이면 round cap/join 으로 이은 선입니다.
    /// </summary>
    private static void Paint(
        DefectCanvas canvas,
        DefectDisplayLocator locator,
        IReadOnlyList<DefectPoint> points,
        double thickness)
    {
        if (points.Count == 0)
        {
            return;
        }
        double lineWidth = Math.Max(1.0, thickness * Math.Min(canvas.Width, canvas.Height));
        DefectMaskOverlayRenderer.DrawPath(
            canvas,
            locator,
            points,
            lineWidth,
            DefectClassPalette.BrushPaint);
    }
}
