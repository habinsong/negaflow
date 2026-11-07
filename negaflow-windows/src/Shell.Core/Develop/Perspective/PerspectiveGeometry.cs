using Negaflow.Catalog;

namespace Negaflow.Shell.Develop.Perspective;

/// <summary>한 크기의 그림에 대한 원근 보정의 정역 호모그래피와 남길 사각형입니다(픽셀 가장자리 좌표, y 아래).</summary>
public sealed record PerspectiveMapping(
    double Width,
    double Height,
    double[] Forward,
    double[] Inverse,
    double OutputLeft,
    double OutputTop,
    double OutputWidth,
    double OutputHeight,
    (double X, double Y)[] Corners);

/// <summary>
/// 원근 보정의 셈입니다. macOS <c>PerspectiveGeometry</c> 와 native <c>perspective_geometry.cpp</c> 와
/// 같은 식·같은 상수입니다 — 한쪽만 바꾸면 화면 좌표와 그림이 어긋납니다.
/// </summary>
public static class PerspectiveGeometry
{
    public const double FocalLength = 1.2;
    public const double SliderDegrees = 35.0;
    public const double MaximumSolvedDegrees = 40.0;
    private const double MinimumDepth = 0.05;

    /// <summary>라디안 축-각 벡터 (가로축, 세로축, 화면축).</summary>
    public static (double X, double Y, double Z) RotationVector(PerspectiveRecipe c)
    {
        ArgumentNullException.ThrowIfNull(c);
        const double radians = Math.PI / 180.0;
        return ((c.SolvedVertical + (c.Vertical / 100.0 * SliderDegrees)) * radians,
                (c.SolvedHorizontal + (c.Horizontal / 100.0 * SliderDegrees)) * radians,
                (c.SolvedRotate + c.Rotate) * radians);
    }

    internal static double[] Multiply(double[] a, double[] b)
    {
        double[] output = new double[9];
        for (int row = 0; row < 3; ++row)
        {
            for (int column = 0; column < 3; ++column)
            {
                double sum = 0;
                for (int k = 0; k < 3; ++k)
                {
                    sum += a[(row * 3) + k] * b[(k * 3) + column];
                }
                output[(row * 3) + column] = sum;
            }
        }
        return output;
    }

    /// <summary>로드리게스 공식(y 아래 카메라 좌표).</summary>
    public static double[] RotationMatrix(double wx, double wy, double wz)
    {
        double angle = Math.Sqrt((wx * wx) + (wy * wy) + (wz * wz));
        if (angle <= 1e-12)
        {
            return [1, 0, 0, 0, 1, 0, 0, 0, 1];
        }
        double kx = wx / angle, ky = wy / angle, kz = wz / angle;
        double[] k = [0, -kz, ky, kz, 0, -kx, -ky, kx, 0];
        double[] k2 = Multiply(k, k);
        double s = Math.Sin(angle), c = 1 - Math.Cos(angle);
        double[] output = [1, 0, 0, 0, 1, 0, 0, 0, 1];
        for (int index = 0; index < 9; ++index)
        {
            output[index] += (s * k[index]) + (c * k2[index]);
        }
        return output;
    }

    public static (double X, double Y)? Apply(double[] m, double x, double y)
    {
        double hx = (m[0] * x) + (m[1] * y) + m[2];
        double hy = (m[3] * x) + (m[4] * y) + m[5];
        double hz = (m[6] * x) + (m[7] * y) + m[8];
        if (Math.Abs(hz) <= 1e-12)
        {
            return null;
        }
        double ox = hx / hz, oy = hy / hz;
        return double.IsFinite(ox) && double.IsFinite(oy) ? (ox, oy) : null;
    }

    private static double[]? Invert(double[] m)
    {
        double a = m[0], b = m[1], c = m[2], d = m[3], e = m[4], f = m[5], g = m[6], h = m[7], i = m[8];
        double det = (a * ((e * i) - (f * h))) - (b * ((d * i) - (f * g))) + (c * ((d * h) - (e * g)));
        if (!double.IsFinite(det) || Math.Abs(det) < 1e-15)
        {
            return null;
        }
        double s = 1.0 / det;
        return
        [
            ((e * i) - (f * h)) * s, ((c * h) - (b * i)) * s, ((b * f) - (c * e)) * s,
            ((f * g) - (d * i)) * s, ((a * i) - (c * g)) * s, ((c * d) - (a * f)) * s,
            ((d * h) - (e * g)) * s, ((b * g) - (a * h)) * s, ((a * e) - (b * d)) * s,
        ];
    }

    /// <summary>보정이 없거나 모서리가 카메라 뒤로 넘어가 그릴 수 없는 값이면 null(그림을 그대로 둡니다).</summary>
    public static PerspectiveMapping? Mapping(PerspectiveRecipe c, double w, double h)
    {
        ArgumentNullException.ThrowIfNull(c);
        if (!c.ChangesGeometry || !c.IsValid || !(w > 1) || !(h > 1))
        {
            return null;
        }
        double s = Math.Max(w, h) / 2;
        double[] toNormal = [1 / s, 0, -w / 2 / s, 0, 1 / s, -h / 2 / s, 0, 0, 1];
        double[] toPixel = [s, 0, w / 2, 0, s, h / 2, 0, 0, 1];
        double f = FocalLength;
        double[] k = [f, 0, 0, 0, f, 0, 0, 0, 1];
        double[] kInverse = [1 / f, 0, 0, 0, 1 / f, 0, 0, 0, 1];
        (double wx, double wy, double wz) = RotationVector(c);
        double stretch = Math.Pow(2, c.Aspect / 200);
        double zoom = c.Scale / 100;
        double[] planar = [zoom * stretch, 0, c.OffsetX / 100 * 0.5, 0, zoom / stretch, c.OffsetY / 100 * 0.5, 0, 0, 1];
        // 기울인 그림의 중심을 프레임 가운데로 되돌립니다(macOS PerspectiveGeometry.homography 와 같은 식).
        double[] tilt = Multiply(Multiply(k, RotationMatrix(wx, wy, wz)), kInverse);
        double[] recenter = tilt[8] > MinimumDepth
            ? [1, 0, -tilt[2] / tilt[8], 0, 1, -tilt[5] / tilt[8], 0, 0, 1]
            : [1, 0, 0, 0, 1, 0, 0, 0, 1];
        double[] forward = Multiply(Multiply(Multiply(Multiply(toPixel, planar), recenter), tilt), toNormal);
        (double X, double Y)[] source = [(0, 0), (w, 0), (w, h), (0, h)];
        (double X, double Y)[] corners = new (double X, double Y)[4];
        for (int index = 0; index < 4; ++index)
        {
            double z = (forward[6] * source[index].X) + (forward[7] * source[index].Y) + forward[8];
            if (!(z > MinimumDepth) || Apply(forward, source[index].X, source[index].Y) is not { } mapped)
            {
                return null;
            }
            corners[index] = mapped;
        }
        if (Invert(forward) is not { } inverse)
        {
            return null;
        }
        if (!c.ConstrainCrop)
        {
            return new PerspectiveMapping(w, h, forward, inverse, 0, 0, w, h, corners);
        }
        (double X, double Y) raw = Apply(forward, w / 2, h / 2) ?? (w / 2, h / 2);
        (double X, double Y) center = (Math.Clamp(raw.X, 1, w - 1), Math.Clamp(raw.Y, 1, h - 1));
        if (!Contains(corners, center))
        {
            return null;
        }
        double aspect = w / h;
        bool Fits(double halfHeight)
        {
            double halfWidth = halfHeight * aspect;
            double left = center.X - halfWidth, right = center.X + halfWidth;
            double top = center.Y - halfHeight, bottom = center.Y + halfHeight;
            if (left < -1e-6 || top < -1e-6 || right > w + 1e-6 || bottom > h + 1e-6)
            {
                return false;
            }
            return Contains(corners, (left, top)) && Contains(corners, (right, top)) &&
                Contains(corners, (right, bottom)) && Contains(corners, (left, bottom));
        }
        double low = 0, high = h / 2;
        for (int iteration = 0; iteration < 40; ++iteration)
        {
            double mid = (low + high) / 2;
            if (Fits(mid))
            {
                low = mid;
            }
            else
            {
                high = mid;
            }
        }
        double hh = low, hw = low * aspect;
        if (hh < 4 || hw < 4)
        {
            return null;
        }
        double x0 = Math.Ceiling(center.X - hw), y0 = Math.Ceiling(center.Y - hh);
        double x1 = Math.Floor(center.X + hw), y1 = Math.Floor(center.Y + hh);
        if (x1 - x0 < 8 || y1 - y0 < 8)
        {
            return null;
        }
        return new PerspectiveMapping(w, h, forward, inverse, x0, y0, x1 - x0, y1 - y0, corners);
    }

    private static bool Contains((double X, double Y)[] polygon, (double X, double Y) p)
    {
        double sign = 0;
        for (int index = 0; index < polygon.Length; ++index)
        {
            (double X, double Y) a = polygon[index];
            (double X, double Y) b = polygon[(index + 1) % polygon.Length];
            double cross = ((b.X - a.X) * (p.Y - a.Y)) - ((b.Y - a.Y) * (p.X - a.X));
            if (Math.Abs(cross) < 1e-9)
            {
                continue;
            }
            double current = cross > 0 ? 1 : -1;
            if (sign == 0)
            {
                sign = current;
            }
            else if (current != sign)
            {
                return false;
            }
        }
        return true;
    }
}
