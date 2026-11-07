using Negaflow.Catalog;

namespace Negaflow.Shell;

/// <summary>화면 위 회전된 사각형입니다. 각도는 라디안이며 화면 기준 시계방향이 양수입니다.</summary>
public readonly record struct FlatbedRegionScreenShape(
    double CenterX,
    double CenterY,
    double Width,
    double Height,
    double Angle)
{
    /// <summary>사각형 자기 좌표(왼쪽 위 원점)를 화면 좌표로 옮깁니다.</summary>
    public (double X, double Y) ScreenPoint(double localX, double localY)
    {
        double dx = localX - (Width / 2);
        double dy = localY - (Height / 2);
        double c = Math.Cos(Angle), s = Math.Sin(Angle);
        return (CenterX + (dx * c) - (dy * s), CenterY + (dx * s) + (dy * c));
    }

    public (double X, double Y) LocalPoint(double screenX, double screenY)
    {
        double dx = screenX - CenterX;
        double dy = screenY - CenterY;
        double c = Math.Cos(Angle), s = Math.Sin(Angle);
        return ((dx * c) + (dy * s) + (Width / 2), (-dx * s) + (dy * c) + (Height / 2));
    }

    /// <summary>자기 좌표 사각형을 같은 회전으로 화면에 놓습니다.</summary>
    public FlatbedRegionScreenShape Reshaped(FlatbedOverlayRect local)
    {
        (double x, double y) = ScreenPoint(local.MidX, local.MidY);
        return new FlatbedRegionScreenShape(x, y, local.Width, local.Height, Angle);
    }

    public (double X, double Y)[] Corners =>
    [
        ScreenPoint(0, 0),
        ScreenPoint(Width, 0),
        ScreenPoint(Width, Height),
        ScreenPoint(0, Height),
    ];

    public FlatbedOverlayRect BoundingRect
    {
        get
        {
            (double X, double Y)[] corners = Corners;
            double minX = corners.Min(point => point.X), maxX = corners.Max(point => point.X);
            double minY = corners.Min(point => point.Y), maxY = corners.Max(point => point.Y);
            return new FlatbedOverlayRect(minX, minY, maxX - minX, maxY - minY);
        }
    }
}

/// <summary>
/// 프레임 하나는 스캔할 물리 영역(원본 좌표의 축 정렬 경계 상자)과 그 안에서 기울어진 필름 칸
/// (<see cref="FlatbedScanRegion.StraightenAngle"/>)을 함께 들고 있습니다. macOS
/// <c>FlatbedScanRegionFrameGeometry</c> 와 같은 셈입니다.
/// </summary>
/// <remarks>
/// 경계 상자를 그대로 화면에 옮기면, 각도가 들어간 프리뷰에서 상자가 실제보다 커 보이고 그
/// 상자를 원본으로 되돌리면 또 커집니다. 프레임을 누를 때마다 커지던 원인이 이 왕복이었습니다.
/// 칸 자체를 오가면 왕복이 정확합니다.
/// </remarks>
public static class FlatbedRegionFrameGeometry
{
    /// <summary>
    /// 화면에서 수평으로 보이는 칸이 원본에서 가져야 할 각도입니다. 가로·세로 중 하나만 뒤집혀
    /// 있으면 같은 회전이 원본에서는 반대 방향입니다(<see cref="FlatbedRegionTransform"/>).
    /// </summary>
    public static double RegionAngle(ImageTransformRecipe? transform)
    {
        if (transform is null || !double.IsFinite(transform.StraightenAngle))
        {
            return 0.0;
        }
        double angle = Math.Clamp(transform.StraightenAngle, -45.0, 45.0);
        return transform.FlipHorizontal != transform.FlipVertical ? -angle : angle;
    }

    /// <summary>
    /// 칸의 네 모서리(원본 정규좌표, y 아래)입니다. 차례는 칸 기준 좌상·우상·우하·좌하입니다.
    /// 경계 상자 <c>Wb×Hb</c> 와 각도로 칸 <c>W×H</c> 를 픽셀 공간에서 풉니다.
    /// </summary>
    public static (double X, double Y)[] FrameCorners(
        double unitX,
        double unitY,
        double unitWidth,
        double unitHeight,
        double straightenAngle,
        uint sourceWidth,
        uint sourceHeight)
    {
        (double X, double Y)[] axis =
        [
            (unitX, unitY),
            (unitX + unitWidth, unitY),
            (unitX + unitWidth, unitY + unitHeight),
            (unitX, unitY + unitHeight),
        ];
        if (Math.Abs(straightenAngle) <= 1.0e-4 || !double.IsFinite(straightenAngle) ||
            sourceWidth <= 1U || sourceHeight <= 1U)
        {
            return axis;
        }
        // 화소 공간은 DevelopDisplayGeometry 와 같은 화소 중심 규약(정규 0·1 = 첫·마지막 화소 중심,
        // 폭 n−1)입니다. macOS 처럼 n 을 쓰면 표시 변환의 회전과 축 비율이 조금 달라져 왕복할
        // 때마다 칸이 미세하게 커지거나 줄어듭니다.
        double pixelWidth = sourceWidth - 1.0, pixelHeight = sourceHeight - 1.0;
        double boundsWidth = unitWidth * pixelWidth;
        double boundsHeight = unitHeight * pixelHeight;
        double radians = straightenAngle * Math.PI / 180.0;
        double c = Math.Abs(Math.Cos(radians)), s = Math.Abs(Math.Sin(radians));
        double determinant = (c * c) - (s * s);
        if (determinant <= 1.0e-6)
        {
            return axis;
        }
        double width = ((boundsWidth * c) - (boundsHeight * s)) / determinant;
        double height = ((boundsHeight * c) - (boundsWidth * s)) / determinant;
        if (width <= 0.0 || height <= 0.0)
        {
            return axis;
        }
        double centerX = (unitX + (unitWidth / 2)) * pixelWidth;
        double centerY = (unitY + (unitHeight / 2)) * pixelHeight;
        (double X, double Y) along = (Math.Cos(radians) * width / 2, -Math.Sin(radians) * width / 2);
        (double X, double Y) across = (Math.Sin(radians) * height / 2, Math.Cos(radians) * height / 2);
        (double A, double B)[] signs = [(-1, -1), (1, -1), (1, 1), (-1, 1)];
        return [.. signs.Select(sign => (
            (centerX + (sign.A * along.X) + (sign.B * across.X)) / pixelWidth,
            (centerY + (sign.A * along.Y) + (sign.B * across.Y)) / pixelHeight))];
    }

    /// <summary>원본 칸을 화면 위 회전 사각형으로 옮깁니다.</summary>
    public static FlatbedRegionScreenShape ScreenShape(
        FlatbedScanRegion region,
        FlatbedOverlayRect imageFrame,
        ImageTransformRecipe? transform,
        uint sourceWidth,
        uint sourceHeight)
    {
        ArgumentNullException.ThrowIfNull(region);
        (double X, double Y)[] corners = FrameCorners(
            region.UnitX, region.UnitY, region.UnitWidth, region.UnitHeight,
            region.StraightenAngle, sourceWidth, sourceHeight);
        (double X, double Y)[] screen = new (double X, double Y)[4];
        for (int index = 0; index < corners.Length; ++index)
        {
            (double x, double y) = corners[index];
            if (transform is not null && sourceWidth > 1U && sourceHeight > 1U &&
                DevelopDisplayGeometry.TryMapRawToDisplay(
                    transform, sourceWidth, sourceHeight, x, y, out double displayX, out double displayY))
            {
                (x, y) = (displayX, displayY);
            }
            screen[index] = (imageFrame.X + (x * imageFrame.Width), imageFrame.Y + (y * imageFrame.Height));
        }
        return ShapeFromScreenCorners(screen);
    }

    /// <summary>
    /// 화면 사각형(회전 포함)을 원본 경계 상자로 되돌립니다. 각도는 그대로 둡니다 — 칸의 네 모서리가
    /// 이미 그 각도로 기울어 있으므로 상자에서 다시 풀면 같은 칸이 나옵니다.
    /// </summary>
    public static (double X, double Y, double Width, double Height) UnitRect(
        FlatbedRegionScreenShape shape,
        FlatbedOverlayRect imageFrame,
        ImageTransformRecipe? transform,
        uint sourceWidth,
        uint sourceHeight)
    {
        double width = Math.Max(imageFrame.Width, 1.0);
        double height = Math.Max(imageFrame.Height, 1.0);
        (double X, double Y)[] corners = shape.Corners;
        (double X, double Y)[] raw = new (double X, double Y)[4];
        for (int index = 0; index < corners.Length; ++index)
        {
            double displayX = (corners[index].X - imageFrame.X) / width;
            double displayY = (corners[index].Y - imageFrame.Y) / height;
            if (transform is not null && sourceWidth > 1U && sourceHeight > 1U &&
                DevelopDisplayGeometry.TryMapDisplayToRaw(
                    transform, sourceWidth, sourceHeight, displayX, displayY, out double x, out double y))
            {
                raw[index] = (x, y);
            }
            else
            {
                raw[index] = (displayX, displayY);
            }
        }
        return Bounds(raw);
    }

    /// <summary>
    /// 칸을 자기 방향으로 눕힌 정규 사각형입니다. 규격 비율 맞춤과 다음 칸 제안이 이 좌표에서 돕니다 —
    /// 픽셀을 칸 각도만큼 펴면 mm 길이가 그대로이므로 기존 셈을 그대로 쓸 수 있습니다.
    /// </summary>
    public static (double X, double Y, double Width, double Height) FrameLocalRect(
        double unitX,
        double unitY,
        double unitWidth,
        double unitHeight,
        double straightenAngle,
        double localAngle,
        uint sourceWidth,
        uint sourceHeight)
    {
        // 기울기가 없으면 모서리를 거치지 않습니다. 모서리로 돌아오면 폭이 (x+w)−x 로 다시 재져
        // 오차가 붙습니다.
        if (Math.Abs(straightenAngle) <= 1.0e-4 && Math.Abs(localAngle) <= 1.0e-4)
        {
            return (unitX, unitY, unitWidth, unitHeight);
        }
        (double X, double Y)[] corners = FrameCorners(
            unitX, unitY, unitWidth, unitHeight, straightenAngle, sourceWidth, sourceHeight);
        return Bounds([.. corners.Select(point => Rotate(point, localAngle, sourceWidth, sourceHeight))]);
    }

    /// <summary><see cref="FrameLocalRect"/> 의 역입니다.</summary>
    public static (double X, double Y, double Width, double Height) UnitRectFromFrameLocal(
        (double X, double Y, double Width, double Height) local,
        double localAngle,
        uint sourceWidth,
        uint sourceHeight)
    {
        if (Math.Abs(localAngle) <= 1.0e-4)
        {
            return local;
        }
        (double X, double Y)[] corners =
        [
            (local.X, local.Y),
            (local.X + local.Width, local.Y),
            (local.X + local.Width, local.Y + local.Height),
            (local.X, local.Y + local.Height),
        ];
        return Bounds([.. corners.Select(point => Rotate(point, -localAngle, sourceWidth, sourceHeight))]);
    }

    /// <summary>
    /// 네 점을 화면 기준으로 가장 덜 기운 회전 사각형으로 읽습니다. 뒤집기·90° 회전이 모서리 차례를
    /// 바꿔도 가로축은 늘 오른쪽, 세로축은 늘 아래를 향하게 고릅니다.
    /// </summary>
    public static FlatbedRegionScreenShape ShapeFromScreenCorners(IReadOnlyList<(double X, double Y)> points)
    {
        ArgumentNullException.ThrowIfNull(points);
        if (points.Count != 4)
        {
            return default;
        }
        double centerX = points.Average(point => point.X);
        double centerY = points.Average(point => point.Y);
        (double X, double Y) u = (points[1].X - points[0].X, points[1].Y - points[0].Y);
        (double X, double Y) v = (points[3].X - points[0].X, points[3].Y - points[0].Y);
        (double X, double Y)[] candidates = [u, v, (-u.X, -u.Y), (-v.X, -v.Y)];
        int best = 0;
        for (int index = 1; index < candidates.Length; ++index)
        {
            if (candidates[index].X > candidates[best].X)
            {
                best = index;
            }
        }
        (double X, double Y) xAxis = candidates[best];
        (double X, double Y) other = best % 2 == 0 ? v : u;
        (double X, double Y) yAxis = other.Y >= 0 ? other : (-other.X, -other.Y);
        return new FlatbedRegionScreenShape(
            centerX,
            centerY,
            Math.Sqrt((xAxis.X * xAxis.X) + (xAxis.Y * xAxis.Y)),
            Math.Sqrt((yAxis.X * yAxis.X) + (yAxis.Y * yAxis.Y)),
            Math.Atan2(xAxis.Y, xAxis.X));
    }

    private static (double X, double Y, double Width, double Height) Bounds(IReadOnlyList<(double X, double Y)> points)
    {
        double minX = points.Min(point => point.X), maxX = points.Max(point => point.X);
        double minY = points.Min(point => point.Y), maxY = points.Max(point => point.Y);
        return (minX, minY, maxX - minX, maxY - minY);
    }

    /// <summary>원본 정규좌표의 점을 픽셀 공간에서 그림 중심 기준으로 돌립니다(y 아래, 양수 = 시계방향).</summary>
    private static (double X, double Y) Rotate((double X, double Y) point, double degrees, uint sourceWidth, uint sourceHeight)
    {
        if (Math.Abs(degrees) <= 1.0e-4 || sourceWidth <= 1U || sourceHeight <= 1U)
        {
            return point;
        }
        // FrameCorners 와 같은 화소 중심 규약입니다.
        double width = sourceWidth - 1.0, height = sourceHeight - 1.0;
        double radians = degrees * Math.PI / 180.0;
        double c = Math.Cos(radians), s = Math.Sin(radians);
        double dx = (point.X * width) - (width / 2);
        double dy = (point.Y * height) - (height / 2);
        return (((width / 2) + (dx * c) - (dy * s)) / width, ((height / 2) + (dx * s) + (dy * c)) / height);
    }
}
