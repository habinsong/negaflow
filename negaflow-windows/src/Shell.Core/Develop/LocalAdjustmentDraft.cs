using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

/// <summary>
/// macOS <c>LocalAdjustmentOverlay</c> 의 끌기 상태(<c>dragStart</c>·<c>dragPoints</c>)입니다.
/// </summary>
/// <remarks>
/// <para>
/// 브러시는 끄는 동안 점을 쌓고, 방사형·선형은 <b>시작점과 지금 점 둘</b>만 들며, 다각형은
/// 끌지 않고 누를 때마다 꼭짓점을 하나씩 찍습니다. macOS 와 같은 규칙입니다.
/// </para>
/// <para>
/// 좌표는 전부 원본 기준 0...1 입니다. 화면 좌표 환산은 캔버스가 합니다.
/// </para>
/// </remarks>
public sealed class LocalAdjustmentDraft
{
    /// <summary>macOS 브러시가 점을 더 쌓기 전에 요구하는 최소 이동입니다(화면 2pt).</summary>
    public const double MinimumBrushStep = 2.0;

    private readonly List<LocalDodgeBurnPoint> points = [];

    public bool IsDragging { get; private set; }

    public IReadOnlyList<LocalDodgeBurnPoint> Points => points;

    /// <summary>끌기를 시작합니다. 다각형은 끌지 않으므로 부르지 않습니다.</summary>
    public void Begin(LocalDodgeBurnPoint start)
    {
        points.Clear();
        points.Add(start);
        IsDragging = true;
    }

    /// <summary>
    /// 끄는 동안 점을 잇습니다. 브러시만 쌓고, 방사형·선형은 끝점 하나만 갈아 끼웁니다.
    /// </summary>
    /// <param name="stepped">
    /// 브러시에서 macOS 의 2pt 문턱을 넘겼는지. 넘지 못한 움직임은 버립니다 — 점이 화면
    /// 픽셀마다 쌓이면 마스크가 수천 점이 됩니다.
    /// </param>
    public void Extend(LocalDodgeBurnMaskKind kind, LocalDodgeBurnPoint point, bool stepped)
    {
        if (!IsDragging)
        {
            return;
        }
        if (kind == LocalDodgeBurnMaskKind.Brush)
        {
            if (stepped)
            {
                points.Add(point);
            }
            return;
        }
        if (points.Count < 2)
        {
            points.Add(point);
            return;
        }
        points[^1] = point;
    }

    /// <summary>
    /// 끌기를 끝내고 쌓인 점을 돌려줍니다. 상태는 비워집니다. macOS <c>finishDrag(at:)</c> 는
    /// 브러시면 쌓인 점 전부를, 나머지는 <b>시작점과 끝점 둘</b>만 씁니다.
    /// </summary>
    public IReadOnlyList<LocalDodgeBurnPoint> End(
        LocalDodgeBurnMaskKind kind,
        LocalDodgeBurnPoint point)
    {
        if (!IsDragging)
        {
            return [];
        }
        LocalDodgeBurnPoint start = points.Count == 0 ? point : points[0];
        LocalDodgeBurnPoint[] result = kind == LocalDodgeBurnMaskKind.Brush
            ? [.. points, point]
            : [start, point];
        Cancel();
        return result;
    }

    public void Cancel()
    {
        points.Clear();
        IsDragging = false;
    }
}
