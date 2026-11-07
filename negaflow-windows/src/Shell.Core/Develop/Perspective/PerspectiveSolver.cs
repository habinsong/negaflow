using Negaflow.Catalog;

namespace Negaflow.Shell.Develop.Perspective;

public readonly record struct PerspectiveSolution(double Vertical, double Horizontal, double Rotate);

/// <summary>
/// 변환 모드의 보정값 찾기입니다. macOS <c>PerspectiveSolver</c> 와 같은 식입니다: 선분을 수직에 가까운
/// 것과 수평에 가까운 것으로 나누고, 모드가 허용하는 회전만 움직여 보정 뒤 선분이 수직·수평에서 벗어난
/// 각도의 가중 합을 가장 작게 만듭니다(Nelder–Mead). 카메라 내부 값이나 소실점은 추정하지 않습니다.
/// </summary>
public static class PerspectiveSolver
{
    private const double ClassificationDegrees = 30.0;
    private const double MinimumDepth = 0.05;

    public static PerspectiveSolution? Solve(
        PerspectiveMode mode, IReadOnlyList<PerspectiveLineSegment> segments, double width, double height)
    {
        ArgumentNullException.ThrowIfNull(segments);
        if (!(width > 1) || !(height > 1) || mode == PerspectiveMode.Off)
        {
            return null;
        }
        double s = Math.Max(width, height) / 2;
        List<(double Ax, double Ay, double Bx, double By, double Length)> verticals = [];
        List<(double Ax, double Ay, double Bx, double By, double Length)> horizontals = [];
        foreach (PerspectiveLineSegment segment in segments)
        {
            double ax = ((segment.StartX * width) - (width / 2)) / s, ay = ((segment.StartY * height) - (height / 2)) / s;
            double bx = ((segment.EndX * width) - (width / 2)) / s, by = ((segment.EndY * height) - (height / 2)) / s;
            double dx = bx - ax, dy = by - ay;
            double length = Math.Sqrt((dx * dx) + (dy * dy));
            if (length <= 1e-4) { continue; }
            double angle = Math.Abs(Math.Atan2(dy, dx) * 180 / Math.PI);
            double fromHorizontal = Math.Min(angle, 180 - angle);
            double fromVertical = Math.Abs(angle - 90);
            if (fromVertical <= ClassificationDegrees)
            {
                verticals.Add((ax, ay, bx, by, length));
            }
            else if (fromHorizontal <= ClassificationDegrees)
            {
                horizontals.Add((ax, ay, bx, by, length));
            }
        }

        bool guided = mode == PerspectiveMode.Guided;
        List<int> free = [2];
        double verticalWeight = 1, horizontalWeight = 1, regularization = 0;
        switch (mode)
        {
            case PerspectiveMode.Level:
                break;
            case PerspectiveMode.Vertical:
                free = [0, 2];
                horizontalWeight = 0.1;
                break;
            case PerspectiveMode.Full:
                free = [0, 1, 2];
                break;
            case PerspectiveMode.Auto:
                free = [0, 1, 2];
                regularization = 1;
                break;
            case PerspectiveMode.Guided:
                if (verticals.Count >= 2) { free.Add(0); }
                if (horizontals.Count >= 2) { free.Add(1); }
                break;
            default:
                return null;
        }
        int totalLines = verticals.Count + horizontals.Count;
        if (guided ? totalLines < 1 : totalLines < 2)
        {
            return null;
        }
        if (free.Contains(0) && verticals.Count < 2) { free.Remove(0); }
        if (free.Contains(1) && horizontals.Count < 2) { free.Remove(1); }

        const double f = PerspectiveGeometry.FocalLength;
        double scale = guided ? 90.0 : 2.0;
        double Loss(double degrees)
        {
            double e = degrees / scale;
            return guided ? e * e : Math.Log(1 + (e * e));
        }
        double Cost(double[] p)
        {
            double[] r = PerspectiveGeometry.RotationMatrix(p[0] * Math.PI / 180, p[1] * Math.PI / 180, p[2] * Math.PI / 180);
            (double X, double Y)? Project(double x, double y)
            {
                double rx = (r[0] * x / f) + (r[1] * y / f) + r[2];
                double ry = (r[3] * x / f) + (r[4] * y / f) + r[5];
                double rz = (r[6] * x / f) + (r[7] * y / f) + r[8];
                return rz > MinimumDepth ? (f * rx / rz, f * ry / rz) : null;
            }
            double total = 0;
            foreach ((double ax, double ay, double bx, double by, double length) in verticals)
            {
                if (Project(ax, ay) is not { } pa || Project(bx, by) is not { } pb) { return double.PositiveInfinity; }
                total += verticalWeight * length * Loss(FoldedVerticalError(pb.X - pa.X, pb.Y - pa.Y));
            }
            foreach ((double ax, double ay, double bx, double by, double length) in horizontals)
            {
                if (Project(ax, ay) is not { } pa || Project(bx, by) is not { } pb) { return double.PositiveInfinity; }
                total += horizontalWeight * length * Loss(FoldedHorizontalError(pb.X - pa.X, pb.Y - pa.Y));
            }
            double tx = p[0] / 10, ty = p[1] / 10;
            total += regularization * Math.Max(totalLines, 1) * 0.02 * ((tx * tx) + (ty * ty));
            return total;
        }
        double[] best = NelderMead([0, 0, 0], free, Cost);
        PerspectiveSolution solution = new(
            Math.Clamp(best[0], -PerspectiveGeometry.MaximumSolvedDegrees, PerspectiveGeometry.MaximumSolvedDegrees),
            Math.Clamp(best[1], -PerspectiveGeometry.MaximumSolvedDegrees, PerspectiveGeometry.MaximumSolvedDegrees),
            Math.Clamp(best[2], -45, 45));
        return double.IsFinite(solution.Vertical) && double.IsFinite(solution.Horizontal) &&
            double.IsFinite(solution.Rotate) ? solution : null;
    }

    internal static double FoldedVerticalError(double dx, double dy)
    {
        double angle = Math.Atan2(dx, dy) * 180 / Math.PI;
        if (angle > 90) { angle -= 180; }
        if (angle < -90) { angle += 180; }
        return angle;
    }

    internal static double FoldedHorizontalError(double dx, double dy)
    {
        double angle = Math.Atan2(dy, dx) * 180 / Math.PI;
        if (angle > 90) { angle -= 180; }
        if (angle < -90) { angle += 180; }
        return angle;
    }

    /// <summary>고른 성분만 움직이는 Nelder–Mead 입니다. 시작 단체는 각 성분 2°.</summary>
    internal static double[] NelderMead(double[] start, IReadOnlyList<int> free, Func<double[], double> cost)
    {
        if (free.Count == 0) { return start; }
        int n = free.Count;
        double[] Point(double[] v)
        {
            double[] p = (double[])start.Clone();
            for (int k = 0; k < n; ++k) { p[free[k]] = v[k]; }
            return p;
        }
        List<double[]> simplex = [[.. free.Select(index => start[index])]];
        for (int k = 0; k < n; ++k)
        {
            double[] v = (double[])simplex[0].Clone();
            v[k] += 2;
            simplex.Add(v);
        }
        List<double> values = [.. simplex.Select(v => cost(Point(v)))];
        for (int iteration = 0; iteration < 400; ++iteration)
        {
            int[] order = [.. Enumerable.Range(0, n + 1).OrderBy(index => values[index])];
            simplex = [.. order.Select(index => simplex[index])];
            values = [.. order.Select(index => values[index])];
            if (Math.Abs(values[n] - values[0]) < 1e-9 * Math.Max(1, Math.Abs(values[0])) &&
                Enumerable.Range(0, n).All(k => Math.Abs(simplex[n][k] - simplex[0][k]) < 1e-4))
            {
                break;
            }
            double[] centroid = new double[n];
            for (int i = 0; i < n; ++i)
            {
                for (int k = 0; k < n; ++k) { centroid[k] += simplex[i][k] / n; }
            }
            double[] Along(double t) => [.. Enumerable.Range(0, n).Select(k => centroid[k] + (t * (simplex[n][k] - centroid[k])))];
            double[] reflected = Along(-1);
            double reflectedValue = cost(Point(reflected));
            if (reflectedValue < values[0])
            {
                double[] expanded = Along(-2);
                double expandedValue = cost(Point(expanded));
                if (expandedValue < reflectedValue) { simplex[n] = expanded; values[n] = expandedValue; }
                else { simplex[n] = reflected; values[n] = reflectedValue; }
            }
            else if (reflectedValue < values[n - 1])
            {
                simplex[n] = reflected;
                values[n] = reflectedValue;
            }
            else
            {
                double[] contracted = reflectedValue < values[n] ? Along(-0.5) : Along(0.5);
                double contractedValue = cost(Point(contracted));
                if (contractedValue < Math.Min(reflectedValue, values[n]))
                {
                    simplex[n] = contracted;
                    values[n] = contractedValue;
                }
                else
                {
                    for (int i = 1; i <= n; ++i)
                    {
                        simplex[i] = [.. Enumerable.Range(0, n).Select(k => simplex[0][k] + (0.5 * (simplex[i][k] - simplex[0][k])))];
                        values[i] = cost(Point(simplex[i]));
                    }
                }
            }
        }
        int bestIndex = Enumerable.Range(0, n + 1).OrderBy(index => values[index]).First();
        return Point(simplex[bestIndex]);
    }
}
