namespace Negaflow.Shell;

/// <summary>프레임 사각형의 크기를 바꾸는 손잡이 여덟 자리입니다.</summary>
public enum FlatbedRegionHandle
{
    TopLeft,
    Top,
    TopRight,
    Right,
    BottomRight,
    Bottom,
    BottomLeft,
    Left,
}

/// <summary>화면 위 사각형입니다. 좌표는 프리뷰 그림이 실제로 그려진 자리 기준입니다.</summary>
public readonly record struct FlatbedOverlayRect(double X, double Y, double Width, double Height)
{
    public double MaxX => X + Width;

    public double MaxY => Y + Height;

    public double MidX => X + (Width / 2);

    public double MidY => Y + (Height / 2);

    public bool Contains(double x, double y) => x >= X && x <= MaxX && y >= Y && y <= MaxY;

    public FlatbedOverlayRect Inset(double dx, double dy) =>
        new(X + dx, Y + dy, Width - (2 * dx), Height - (2 * dy));

    public FlatbedOverlayRect OffsetBy(double dx, double dy) => this with { X = X + dx, Y = Y + dy };
}

/// <summary>
/// 오버레이의 순수한 셈입니다. macOS <c>FlatbedScanAreaOverlayGeometry</c> 를 그대로 옮긴
/// 것이며, 화면 요소 없이 시험할 수 있도록 Shell.Core 에 둡니다.
/// </summary>
public static class FlatbedOverlayGeometry
{
    /// <summary>손잡이의 눈에 보이는 크기입니다. 집는 자리는 이보다 넓습니다.</summary>
    public const double HandleHitSize = 24.0;

    /// <summary>
    /// 여기서 새 프레임을 그리기 시작해도 되는지입니다. 이미 놓인 프레임 근처면 그리기가
    /// 아니라 그 프레임을 끄는 것으로 봅니다.
    /// </summary>
    public static bool CanBeginCreation(
        double x,
        double y,
        IReadOnlyList<FlatbedOverlayRect> existing,
        double exclusionPadding = 12.0)
    {
        ArgumentNullException.ThrowIfNull(existing);
        foreach (FlatbedOverlayRect rect in existing)
        {
            if (rect.Inset(-exclusionPadding, -exclusionPadding).Contains(x, y))
            {
                return false;
            }
        }
        return true;
    }

    /// <summary>손잡이를 끌었을 때의 새 사각형입니다. 경계를 넘지 않고 최소 크기를 지킵니다.</summary>
    public static FlatbedOverlayRect ResizedRect(
        FlatbedOverlayRect start,
        double pointX,
        double pointY,
        FlatbedRegionHandle handle,
        FlatbedOverlayRect bounds,
        double minimumSize = 12.0)
    {
        pointX = Math.Clamp(pointX, bounds.X, bounds.MaxX);
        pointY = Math.Clamp(pointY, bounds.Y, bounds.MaxY);
        double minX = Math.Max(start.X, bounds.X);
        double maxX = Math.Min(start.MaxX, bounds.MaxX);
        double minY = Math.Max(start.Y, bounds.Y);
        double maxY = Math.Min(start.MaxY, bounds.MaxY);
        double minimumWidth = Math.Clamp(minimumSize, 0, bounds.Width);
        double minimumHeight = Math.Clamp(minimumSize, 0, bounds.Height);

        switch (handle)
        {
            case FlatbedRegionHandle.TopLeft:
                minX = Math.Min(pointX, Math.Max(bounds.X, maxX - minimumWidth));
                minY = Math.Min(pointY, Math.Max(bounds.Y, maxY - minimumHeight));
                break;
            case FlatbedRegionHandle.Top:
                minY = Math.Min(pointY, Math.Max(bounds.Y, maxY - minimumHeight));
                break;
            case FlatbedRegionHandle.TopRight:
                maxX = Math.Max(pointX, Math.Min(bounds.MaxX, minX + minimumWidth));
                minY = Math.Min(pointY, Math.Max(bounds.Y, maxY - minimumHeight));
                break;
            case FlatbedRegionHandle.Right:
                maxX = Math.Max(pointX, Math.Min(bounds.MaxX, minX + minimumWidth));
                break;
            case FlatbedRegionHandle.BottomRight:
                maxX = Math.Max(pointX, Math.Min(bounds.MaxX, minX + minimumWidth));
                maxY = Math.Max(pointY, Math.Min(bounds.MaxY, minY + minimumHeight));
                break;
            case FlatbedRegionHandle.Bottom:
                maxY = Math.Max(pointY, Math.Min(bounds.MaxY, minY + minimumHeight));
                break;
            case FlatbedRegionHandle.BottomLeft:
                minX = Math.Min(pointX, Math.Max(bounds.X, maxX - minimumWidth));
                maxY = Math.Max(pointY, Math.Min(bounds.MaxY, minY + minimumHeight));
                break;
            case FlatbedRegionHandle.Left:
                minX = Math.Min(pointX, Math.Max(bounds.X, maxX - minimumWidth));
                break;
            default:
                break;
        }

        return new FlatbedOverlayRect(minX, minY, maxX - minX, maxY - minY);
    }

    /// <summary>사각형 안에서 손잡이가 앉는 자리입니다(사각형 왼쪽 위가 원점).</summary>
    public static (double X, double Y) HandlePoint(
        FlatbedRegionHandle handle,
        double width,
        double height) => handle switch
        {
            FlatbedRegionHandle.TopLeft => (0, 0),
            FlatbedRegionHandle.Top => (width / 2, 0),
            FlatbedRegionHandle.TopRight => (width, 0),
            FlatbedRegionHandle.Right => (width, height / 2),
            FlatbedRegionHandle.BottomRight => (width, height),
            FlatbedRegionHandle.Bottom => (width / 2, height),
            FlatbedRegionHandle.BottomLeft => (0, height),
            FlatbedRegionHandle.Left => (0, height / 2),
            _ => (0, 0),
        };

    /// <summary>손잡이의 눈에 보이는 크기입니다. 변은 길쭉하고 모서리는 정사각입니다.</summary>
    public static (double Width, double Height) HandleSize(FlatbedRegionHandle handle) => handle switch
    {
        FlatbedRegionHandle.Top or FlatbedRegionHandle.Bottom => (18, 8),
        FlatbedRegionHandle.Left or FlatbedRegionHandle.Right => (8, 18),
        _ => (12, 12),
    };

    /// <summary>
    /// 그림이 실제로 그려지는 자리입니다. 비율을 지켜 가운데에 맞춰 넣습니다 - macOS
    /// <c>canvasFittedImageFrame</c> 과 같은 규칙입니다.
    /// </summary>
    public static FlatbedOverlayRect FittedImageFrame(
        double imageWidth,
        double imageHeight,
        double hostWidth,
        double hostHeight)
    {
        if (imageWidth <= 0 || imageHeight <= 0 || hostWidth <= 0 || hostHeight <= 0)
        {
            return default;
        }
        double scale = Math.Min(hostWidth / imageWidth, hostHeight / imageHeight);
        double width = imageWidth * scale;
        double height = imageHeight * scale;
        return new FlatbedOverlayRect(
            (hostWidth - width) / 2,
            (hostHeight - height) / 2,
            width,
            height);
    }

    /// <summary>프레임의 비율 좌표를 화면 자리로 폅니다.</summary>
    public static FlatbedOverlayRect ScreenRect(
        FlatbedScanRegion region,
        FlatbedOverlayRect imageFrame)
    {
        ArgumentNullException.ThrowIfNull(region);
        return new FlatbedOverlayRect(
            imageFrame.X + (region.UnitX * imageFrame.Width),
            imageFrame.Y + (region.UnitY * imageFrame.Height),
            region.UnitWidth * imageFrame.Width,
            region.UnitHeight * imageFrame.Height);
    }

    /// <summary>화면 자리를 프레임의 비율 좌표로 되돌립니다.</summary>
    public static (double X, double Y, double Width, double Height) UnitRect(
        FlatbedOverlayRect screenRect,
        FlatbedOverlayRect imageFrame)
    {
        double width = Math.Max(imageFrame.Width, 1);
        double height = Math.Max(imageFrame.Height, 1);
        return (
            (screenRect.X - imageFrame.X) / width,
            (screenRect.Y - imageFrame.Y) / height,
            screenRect.Width / width,
            screenRect.Height / height);
    }

    /// <summary>화면의 한 점을 프리뷰 안의 비율로 되돌립니다. 그림 밖은 가장자리로 접습니다.</summary>
    public static (double X, double Y) UnitPoint(
        double x,
        double y,
        FlatbedOverlayRect imageFrame) =>
        (
            Math.Clamp((x - imageFrame.X) / Math.Max(imageFrame.Width, 1), 0, 1),
            Math.Clamp((y - imageFrame.Y) / Math.Max(imageFrame.Height, 1), 0, 1));

    /// <summary>끌어서 만든 사각형을 그림 안으로 접고 최소 크기를 지킵니다.</summary>
    public static FlatbedOverlayRect ClampedScreenRect(
        FlatbedOverlayRect rect,
        FlatbedOverlayRect imageFrame,
        double minimum = 12.0)
    {
        double width = Math.Clamp(rect.Width, minimum, Math.Max(imageFrame.Width, minimum));
        double height = Math.Clamp(rect.Height, minimum, Math.Max(imageFrame.Height, minimum));
        return new FlatbedOverlayRect(
            Math.Clamp(rect.X, imageFrame.X, Math.Max(imageFrame.X, imageFrame.MaxX - width)),
            Math.Clamp(rect.Y, imageFrame.Y, Math.Max(imageFrame.Y, imageFrame.MaxY - height)),
            width,
            height);
    }

    /// <summary>두 점으로 사각형을 만듭니다. 어느 쪽으로 끌든 양수 크기가 나옵니다.</summary>
    public static FlatbedOverlayRect RectBetween(double x1, double y1, double x2, double y2) =>
        new(
            Math.Min(x1, x2),
            Math.Min(y1, y2),
            Math.Abs(x2 - x1),
            Math.Abs(y2 - y1));
}
