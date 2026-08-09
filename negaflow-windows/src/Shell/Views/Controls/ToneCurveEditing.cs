using Negaflow.Catalog;

namespace Negaflow.Shell.Views.Controls;

internal enum ToneCurveChannel
{
    Rgb,
    Red,
    Green,
    Blue,
}

/// <summary>
/// UI 독립적인 Point Curve 편집 규칙입니다. Canvas와 키보드가 같은 0...1 좌표·점 간격
/// 제약을 사용하도록 분리해, 화면 코드가 recipe mutation을 직접 소유하지 않게 합니다.
/// </summary>
internal sealed class ToneCurveEditing
{
    private const double EndpointEpsilon = 1.0e-9;
    private const double MinimumUiSpacing = 0.01;

    private PointCurveRecipe curves = PointCurveRecipe.Identity;

    public ToneCurveChannel Channel { get; private set; }

    public int SelectedIndex { get; private set; } = -1;

    public PointCurveRecipe Curves => curves;

    public IReadOnlyList<PointCurvePoint> Points => GetPoints(Channel);

    public void SetCurves(PointCurveRecipe value)
    {
        ArgumentNullException.ThrowIfNull(value);
        curves = value;
        SelectedIndex = -1;
    }

    public void SetChannel(ToneCurveChannel value)
    {
        Channel = value;
        SelectedIndex = -1;
    }

    public bool TrySelectNearest(double x, double y, double hitRadius)
    {
        int candidate = -1;
        double bestDistanceSquared = hitRadius * hitRadius;
        for (int index = 0; index < Points.Count; index++)
        {
            PointCurvePoint point = Points[index];
            double distanceSquared = ((point.X - x) * (point.X - x)) +
                ((point.Y - y) * (point.Y - y));
            if (distanceSquared <= bestDistanceSquared)
            {
                candidate = index;
                bestDistanceSquared = distanceSquared;
            }
        }

        SelectedIndex = candidate;
        return candidate >= 0;
    }

    public bool Add(double x, double y)
    {
        if (Points.Count >= PointCurveRecipe.MaximumPointsPerChannel)
        {
            return false;
        }

        List<PointCurvePoint> updated = Points.ToList();
        int insertionIndex = updated.FindIndex(point => point.X > x);
        if (insertionIndex < 0)
        {
            insertionIndex = updated.Count;
        }

        double minimumX = insertionIndex == 0
            ? 0.0
            : updated[insertionIndex - 1].X + MinimumUiSpacing;
        double maximumX = insertionIndex == updated.Count
            ? 1.0
            : updated[insertionIndex].X - MinimumUiSpacing;
        if (minimumX > maximumX)
        {
            return false;
        }

        updated.Insert(insertionIndex, new PointCurvePoint(
            Math.Clamp(x, minimumX, maximumX),
            Math.Clamp(y, 0.0, 1.0)));
        SetPoints(updated, insertionIndex);
        return true;
    }

    public bool AddLargestGap()
    {
        if (Points.Count == 0)
        {
            return Add(0.5, 0.5);
        }

        double bestStart = 0.0;
        double bestEnd = 0.0;
        int insertionIndex = 0;
        double previousX = 0.0;
        for (int index = 0; index <= Points.Count; index++)
        {
            double nextX = index == Points.Count ? 1.0 : Points[index].X;
            if (nextX - previousX > bestEnd - bestStart)
            {
                bestStart = previousX;
                bestEnd = nextX;
                insertionIndex = index;
            }
            previousX = nextX;
        }

        double x = (bestStart + bestEnd) / 2.0;
        double y = Interpolate(x);
        return Add(x, y);
    }

    public bool UpdateSelected(double x, double y)
    {
        if (SelectedIndex < 0 || SelectedIndex >= Points.Count)
        {
            return false;
        }

        List<PointCurvePoint> updated = Points.ToList();
        PointCurvePoint selected = updated[SelectedIndex];
        double resolvedX = selected.X;
        if (selected.X > EndpointEpsilon && selected.X < 1.0 - EndpointEpsilon)
        {
            double minimumX = SelectedIndex == 0
                ? 0.0
                : updated[SelectedIndex - 1].X + MinimumUiSpacing;
            double maximumX = SelectedIndex == updated.Count - 1
                ? 1.0
                : updated[SelectedIndex + 1].X - MinimumUiSpacing;
            // Catalog accepts the native 1e-9 spacing; a pre-existing dense curve
            // has no valid 1% UI drag interval, so preserve its x rather than throw.
            if (minimumX <= maximumX)
            {
                resolvedX = Math.Clamp(x, minimumX, maximumX);
            }
        }
        updated[SelectedIndex] = new PointCurvePoint(resolvedX, Math.Clamp(y, 0.0, 1.0));
        SetPoints(updated, SelectedIndex);
        return true;
    }

    public bool NudgeSelected(bool horizontal, bool increase, bool coarse)
    {
        if (SelectedIndex < 0 || SelectedIndex >= Points.Count)
        {
            return false;
        }

        PointCurvePoint selected = Points[SelectedIndex];
        double delta = coarse ? 0.05 : 0.01;
        return UpdateSelected(
            horizontal ? selected.X + (increase ? delta : -delta) : selected.X,
            horizontal ? selected.Y : selected.Y + (increase ? delta : -delta));
    }

    public bool DeleteSelected()
    {
        if (SelectedIndex < 0 || SelectedIndex >= Points.Count)
        {
            return false;
        }

        PointCurvePoint selected = Points[SelectedIndex];
        if (selected.X <= EndpointEpsilon || selected.X >= 1.0 - EndpointEpsilon)
        {
            return false;
        }

        List<PointCurvePoint> updated = Points.ToList();
        updated.RemoveAt(SelectedIndex);
        SetPoints(updated, Math.Min(SelectedIndex, updated.Count - 1));
        return true;
    }

    public void ResetChannel()
    {
        SetPoints([], -1);
    }

    private double Interpolate(double x)
    {
        if (Points.Count == 0)
        {
            return x;
        }

        PointCurvePoint previous = new(0.0, 0.0);
        foreach (PointCurvePoint point in Points)
        {
            if (x <= point.X)
            {
                double span = point.X - previous.X;
                return span <= EndpointEpsilon
                    ? point.Y
                    : previous.Y + ((point.Y - previous.Y) * ((x - previous.X) / span));
            }
            previous = point;
        }

        return previous.X >= 1.0 - EndpointEpsilon
            ? previous.Y
            : previous.Y + ((1.0 - previous.Y) * ((x - previous.X) / (1.0 - previous.X)));
    }

    private IReadOnlyList<PointCurvePoint> GetPoints(ToneCurveChannel channel) => channel switch
    {
        ToneCurveChannel.Rgb => curves.Rgb,
        ToneCurveChannel.Red => curves.Red,
        ToneCurveChannel.Green => curves.Green,
        ToneCurveChannel.Blue => curves.Blue,
        _ => throw new ArgumentOutOfRangeException(nameof(channel)),
    };

    private void SetPoints(IReadOnlyList<PointCurvePoint> points, int selectedIndex)
    {
        PointCurvePoint[] ordered = points.OrderBy(point => point.X).ToArray();
        curves = Channel switch
        {
            ToneCurveChannel.Rgb => curves with { Rgb = ordered },
            ToneCurveChannel.Red => curves with { Red = ordered },
            ToneCurveChannel.Green => curves with { Green = ordered },
            ToneCurveChannel.Blue => curves with { Blue = ordered },
            _ => throw new ArgumentOutOfRangeException(),
        };
        SelectedIndex = selectedIndex;
    }
}
