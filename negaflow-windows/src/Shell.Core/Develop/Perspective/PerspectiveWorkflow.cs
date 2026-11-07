using Negaflow.Catalog;

namespace Negaflow.Shell.Develop.Perspective;

/// <summary>
/// 변환 모드를 고르거나 안내선을 바꿀 때의 셈입니다. 화면 ↔ 원본 ↔ 원근 보정 앞 좌표를 오가고,
/// 자동 모드는 화면에 그려진 현상본에서 선을 찾아 원근 보정 앞 좌표로 되돌려 풉니다 — 원근·수평
/// 보정·크롭은 모두 직선을 직선으로 보내므로 화면에서 찾은 선분을 그대로 옮길 수 있습니다.
/// </summary>
public static class PerspectiveWorkflow
{
    /// <summary>회전·뒤집기만 건 그림(원근 보정 입력)의 정규좌표 → 원본 정규좌표.</summary>
    public static (double X, double Y) OrientedToRaw(ImageTransformRecipe transform, double x, double y)
    {
        ArgumentNullException.ThrowIfNull(transform);
        (x, y) = transform.Rotation switch
        {
            ImageRotation.Degrees90 => (y, 1 - x),
            ImageRotation.Degrees180 => (1 - x, 1 - y),
            ImageRotation.Degrees270 => (1 - y, x),
            _ => (x, y),
        };
        if (transform.FlipVertical) { y = 1 - y; }
        if (transform.FlipHorizontal) { x = 1 - x; }
        return (x, y);
    }

    public static (double X, double Y) RawToOriented(ImageTransformRecipe transform, double x, double y)
    {
        ArgumentNullException.ThrowIfNull(transform);
        if (transform.FlipHorizontal) { x = 1 - x; }
        if (transform.FlipVertical) { y = 1 - y; }
        return transform.Rotation switch
        {
            ImageRotation.Degrees90 => (1 - y, x),
            ImageRotation.Degrees180 => (1 - x, 1 - y),
            ImageRotation.Degrees270 => (y, 1 - x),
            _ => (x, y),
        };
    }

    public static (double Width, double Height) OrientedSize(ImageTransformRecipe transform, uint width, uint height)
    {
        ArgumentNullException.ThrowIfNull(transform);
        return transform.Rotation is ImageRotation.Degrees90 or ImageRotation.Degrees270
            ? (height, width)
            : (width, height);
    }

    /// <summary>도우미 안내선으로 다시 풉니다. 안내선이 모자라면 푼 값을 0 으로 둡니다.</summary>
    public static PerspectiveRecipe WithGuidedSolution(
        PerspectiveRecipe perspective, ImageTransformRecipe transform, uint width, uint height)
    {
        ArgumentNullException.ThrowIfNull(perspective);
        (double w, double h) = OrientedSize(transform, width, height);
        PerspectiveLineSegment[] segments = [.. perspective.Guides.Select(guide =>
            new PerspectiveLineSegment(guide.StartX, guide.StartY, guide.EndX, guide.EndY, 1))];
        PerspectiveSolution? solution = width > 1 && height > 1
            ? PerspectiveSolver.Solve(PerspectiveMode.Guided, segments, w, h)
            : null;
        return perspective with
        {
            Mode = PerspectiveMode.Guided,
            SolvedVertical = solution?.Vertical ?? 0,
            SolvedHorizontal = solution?.Horizontal ?? 0,
            SolvedRotate = solution?.Rotate ?? 0,
        };
    }

    /// <summary>
    /// 화면에 그려진 현상본(BGRA8, 감마)에서 선을 찾아 <paramref name="mode"/> 로 풉니다. 쓸 선이
    /// 모자라면 null 입니다.
    /// </summary>
    public static PerspectiveSolution? SolveFromDisplay(
        byte[] bgra,
        int displayWidth,
        int displayHeight,
        ImageTransformRecipe transform,
        uint sourceWidth,
        uint sourceHeight,
        PerspectiveMode mode)
    {
        ArgumentNullException.ThrowIfNull(bgra);
        ArgumentNullException.ThrowIfNull(transform);
        if (displayWidth < 16 || displayHeight < 16 || bgra.Length < displayWidth * displayHeight * 4 ||
            sourceWidth < 2 || sourceHeight < 2)
        {
            return null;
        }
        double scale = Math.Min(1.0, (double)PerspectiveLineDetector.AnalysisLongEdge / Math.Max(displayWidth, displayHeight));
        int width = Math.Max(16, (int)(displayWidth * scale));
        int height = Math.Max(16, (int)(displayHeight * scale));
        float[] luma = new float[width * height];
        // 칸 평균으로 줄입니다. 감마 밝기를 그대로 써서 사람 눈에 보이는 가장자리를 찾습니다.
        for (int y = 0; y < height; ++y)
        {
            int y0 = y * displayHeight / height, y1 = Math.Max(y0 + 1, (y + 1) * displayHeight / height);
            for (int x = 0; x < width; ++x)
            {
                int x0 = x * displayWidth / width, x1 = Math.Max(x0 + 1, (x + 1) * displayWidth / width);
                double sum = 0;
                int count = 0;
                for (int sy = y0; sy < y1; ++sy)
                {
                    for (int sx = x0; sx < x1; ++sx)
                    {
                        int i = ((sy * displayWidth) + sx) * 4;
                        sum += (0.0722 * bgra[i]) + (0.7152 * bgra[i + 1]) + (0.2126 * bgra[i + 2]);
                        count += 1;
                    }
                }
                luma[(y * width) + x] = (float)(sum / count / 255.0);
            }
        }
        List<PerspectiveLineSegment> oriented = [];
        foreach (PerspectiveLineSegment segment in PerspectiveLineDetector.Detect(luma, width, height))
        {
            // 보정이 이미 걸린 그림에는 원본 바깥(흰 빈 영역)이 있고, 그 경계는 원본 테두리 —
            // 완벽한 수직·수평선 — 로 되돌아가 "보정 0" 쪽으로 풀이를 끌어당깁니다. 사진 안쪽에
            // 온전히 들어 있는 선분만 씁니다.
            if (!InsideSource(segment, width, height))
            {
                continue;
            }
            if (ToOriented(segment.StartX, segment.StartY) is { } a && ToOriented(segment.EndX, segment.EndY) is { } b)
            {
                oriented.Add(new PerspectiveLineSegment(a.X, a.Y, b.X, b.Y, segment.Length));
            }
        }
        (double w, double h) = OrientedSize(transform, sourceWidth, sourceHeight);
        return PerspectiveSolver.Solve(mode, oriented, w, h);

        // 선분 위와 양옆(분석 화소 3칸)의 점이 모두 원본 안에 떨어지는지 봅니다. 원본 바깥의 점은
        // 원본 좌표가 테두리로 잘려 화면으로 되돌리면 제자리에 오지 않습니다.
        bool InsideSource(PerspectiveLineSegment segment, int analysisWidth, int analysisHeight)
        {
            double dx = (segment.EndX - segment.StartX) * analysisWidth;
            double dy = (segment.EndY - segment.StartY) * analysisHeight;
            double length = Math.Sqrt((dx * dx) + (dy * dy));
            if (length < 1e-9)
            {
                return false;
            }
            const double margin = 3.0;
            double nx = -dy / length * margin / analysisWidth;
            double ny = dx / length * margin / analysisHeight;
            double toleranceX = 0.75 / Math.Max(displayWidth - 1, 1);
            double toleranceY = 0.75 / Math.Max(displayHeight - 1, 1);
            for (int i = 0; i <= 4; ++i)
            {
                double t = i / 4.0;
                double x = segment.StartX + ((segment.EndX - segment.StartX) * t);
                double y = segment.StartY + ((segment.EndY - segment.StartY) * t);
                for (int side = -1; side <= 1; ++side)
                {
                    double px = x + (side * nx), py = y + (side * ny);
                    if (px < 0 || px > 1 || py < 0 || py > 1 ||
                        !DevelopDisplayGeometry.TryMapDisplayToRaw(
                            transform, sourceWidth, sourceHeight, px, py, out double rawX, out double rawY) ||
                        !DevelopDisplayGeometry.TryMapRawToDisplay(
                            transform, sourceWidth, sourceHeight, rawX, rawY, out double backX, out double backY) ||
                        Math.Abs(backX - px) > toleranceX || Math.Abs(backY - py) > toleranceY)
                    {
                        return false;
                    }
                }
            }
            return true;
        }

        (double X, double Y)? ToOriented(double displayX, double displayY) =>
            DevelopDisplayGeometry.TryMapDisplayToRaw(
                transform, sourceWidth, sourceHeight, displayX, displayY, out double rawX, out double rawY)
                ? RawToOriented(transform, rawX, rawY)
                : null;
    }
}
