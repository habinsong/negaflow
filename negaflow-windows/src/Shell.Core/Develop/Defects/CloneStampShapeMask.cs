namespace Negaflow.Shell.Develop;

/// <summary>
/// macOS 복제 도장이 소스 창을 잘라 내는 모양입니다 — 커서 원
/// (<c>clip(to: Path(ellipseIn: rect))</c>) 과 진행 중인 획
/// (<c>clip(to: strokeShape(current, diameter:))</c>) 입니다.
/// </summary>
/// <remarks>
/// <para>
/// macOS <c>strokeShape</c> 는 점이 하나면 그 지름의 원, 여럿이면
/// <c>strokedPath(StrokeStyle(lineWidth: diameter, lineCap: .round, lineJoin: .round))</c> 입니다.
/// round cap/join 으로 그은 선의 모양은 <b>선 위 모든 점을 중심으로 한 반지름 r 원들의 합집합</b>과
/// 같으므로, 선분을 따라 원을 촘촘히 찍어 같은 모양을 냅니다 —
/// <see cref="DefectMaskOverlayRenderer.Stamp"/> 가 이미 쓰는 방법입니다.
/// </para>
/// <para>
/// 표시할 것은 화소마다 <b>한 번만</b> 그려야 합니다. macOS 는 잘라 낸 뒤 이미지를 한 번 그리므로
/// 겹치는 자리도 한 번입니다. 그래서 찍는 동안에는 표시만 해 두고, 옮기는 것은 나중에 한 번 합니다.
/// </para>
/// <para>
/// 표는 모양의 경계 상자만큼만 잡습니다. 포인터가 움직일 때마다 화면 전체 크기를 새로 잡으면
/// 손을 젓는 동안 수십 MB 를 버립니다.
/// </para>
/// </remarks>
internal sealed class CloneStampShapeMask
{
    private readonly bool[] cells;
    private readonly int columns;

    private CloneStampShapeMask(int left, int top, int right, int bottom)
    {
        Left = left;
        Top = top;
        Right = right;
        Bottom = bottom;
        columns = right - left + 1;
        cells = new bool[checked(columns * (bottom - top + 1))];
    }

    public int Left { get; }

    public int Top { get; }

    public int Right { get; }

    public int Bottom { get; }

    public bool Contains(int x, int y) =>
        x >= Left && x <= Right && y >= Top && y <= Bottom &&
        cells[((y - Top) * columns) + (x - Left)];

    /// <summary>macOS <c>Path(ellipseIn: rect)</c> — 지름 <c>diameter</c> 의 채운 원입니다.</summary>
    public static CloneStampShapeMask? ForDisc(
        int centerX,
        int centerY,
        double radius,
        int width,
        int height)
    {
        if (radius < 0.0 || width <= 0 || height <= 0)
        {
            return null;
        }
        int extent = (int)Math.Ceiling(radius);
        if (Bounds(
                centerX - extent,
                centerY - extent,
                centerX + extent,
                centerY + extent,
                width,
                height) is not { } mask)
        {
            return null;
        }
        mask.Stamp(centerX, centerY, radius);
        return mask;
    }

    /// <summary>
    /// macOS <c>strokeShape(pts, diameter:)</c> — 점이 하나면 원, 여럿이면 round cap/join 으로
    /// 이은 선입니다.
    /// </summary>
    public static CloneStampShapeMask? ForStroke(
        IReadOnlyList<(int X, int Y)> points,
        double radius,
        int width,
        int height)
    {
        ArgumentNullException.ThrowIfNull(points);
        if (points.Count == 0 || radius < 0.0 || width <= 0 || height <= 0)
        {
            return null;
        }
        int extent = (int)Math.Ceiling(radius);
        int minX = int.MaxValue;
        int minY = int.MaxValue;
        int maxX = int.MinValue;
        int maxY = int.MinValue;
        foreach ((int x, int y) in points)
        {
            minX = Math.Min(minX, x);
            minY = Math.Min(minY, y);
            maxX = Math.Max(maxX, x);
            maxY = Math.Max(maxY, y);
        }
        if (Bounds(
                minX - extent,
                minY - extent,
                maxX + extent,
                maxY + extent,
                width,
                height) is not { } mask)
        {
            return null;
        }

        if (points.Count == 1)
        {
            mask.Stamp(points[0].X, points[0].Y, radius);
            return mask;
        }
        for (int index = 1; index < points.Count; ++index)
        {
            mask.StampSegment(points[index - 1], points[index], radius);
        }
        return mask;
    }

    /// <summary>화면과 겹치는 부분만 남깁니다. 겹치는 것이 없으면 표를 잡지 않습니다.</summary>
    private static CloneStampShapeMask? Bounds(
        int left,
        int top,
        int right,
        int bottom,
        int width,
        int height)
    {
        int clampedLeft = Math.Max(0, left);
        int clampedTop = Math.Max(0, top);
        int clampedRight = Math.Min(width - 1, right);
        int clampedBottom = Math.Min(height - 1, bottom);
        return clampedRight < clampedLeft || clampedBottom < clampedTop
            ? null
            : new CloneStampShapeMask(clampedLeft, clampedTop, clampedRight, clampedBottom);
    }

    private void StampSegment((int X, int Y) from, (int X, int Y) to, double radius)
    {
        int steps = Math.Max(Math.Abs(to.X - from.X), Math.Abs(to.Y - from.Y));
        if (steps == 0)
        {
            Stamp(from.X, from.Y, radius);
            return;
        }
        for (int step = 0; step <= steps; ++step)
        {
            double t = (double)step / steps;
            Stamp(
                (int)Math.Round(from.X + ((to.X - from.X) * t)),
                (int)Math.Round(from.Y + ((to.Y - from.Y) * t)),
                radius);
        }
    }

    /// <summary>
    /// <see cref="DefectCanvas.FillCircle"/> 과 <b>같은 화소 집합</b>인 원입니다
    /// (<c>dx² + dy² ≤ radius²</c>). 두 표면이 같은 모양이어야 합니다.
    /// </summary>
    /// <remarks>
    /// 행마다 반너비를 구해 <see cref="Array.Fill{T}(T[], T, int, int)"/> 로 한 번에 채웁니다.
    /// 화소마다 거리를 재면 원 하나가 O(r²) 이고, 획은 1화소 간격으로 원을 찍으므로 크기를
    /// 512px 로 올린 긴 획에서 한 프레임에 <b>49.8ms</b> 가 들었습니다(계측기
    /// <c>--clone-cursor-bench</c>). 행 단위로 바꾸면 원 하나가 O(r) 입니다.
    /// </remarks>
    private void Stamp(int centerX, int centerY, double radius)
    {
        if (radius < 0.5)
        {
            Mark(centerX, centerY);
            return;
        }
        double squared = radius * radius;
        int extent = (int)Math.Ceiling(radius);
        int top = Math.Max(Top, centerY - extent);
        int bottom = Math.Min(Bottom, centerY + extent);
        for (int y = top; y <= bottom; ++y)
        {
            double dy = y - centerY;
            double remaining = squared - (dy * dy);
            if (remaining < 0.0)
            {
                continue;
            }
            int half = HalfWidth(remaining);
            int left = Math.Max(Left, centerX - half);
            int right = Math.Min(Right, centerX + half);
            if (right < left)
            {
                continue;
            }
            Array.Fill(cells, true, ((y - Top) * columns) + (left - Left), right - left + 1);
        }
    }

    /// <summary>
    /// <c>dx² ≤ remaining</c> 을 만족하는 가장 큰 정수입니다. <see cref="Math.Sqrt"/> 가 한 눈금
    /// 어긋나도 원의 화소 집합이 달라지지 않게 한 걸음 고칩니다.
    /// </summary>
    private static int HalfWidth(double remaining)
    {
        int half = (int)Math.Sqrt(remaining);
        if ((double)(half + 1) * (half + 1) <= remaining)
        {
            return half + 1;
        }
        return (double)half * half > remaining ? half - 1 : half;
    }

    private void Mark(int x, int y)
    {
        if (x < Left || x > Right || y < Top || y > Bottom)
        {
            return;
        }
        cells[((y - Top) * columns) + (x - Left)] = true;
    }
}
