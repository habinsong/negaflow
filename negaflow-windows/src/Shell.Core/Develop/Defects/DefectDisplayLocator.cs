using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

/// <summary>
/// 원본 정규 좌표를 표시 화소로 되돌립니다.
/// </summary>
/// <remarks>
/// <see cref="DevelopDisplayGeometry.TryMapRawToDisplay"/>가 macOS
/// <c>ImageTransform.baseUnitToDisplay</c>와 같은 직접 변환을 소유합니다. 고정 해상도 역조회 표를
/// 만들지 않아 작은 preview에서도 원본 점을 누락하지 않습니다.
/// </remarks>
public sealed class DefectDisplayLocator
{
    private readonly ImageTransformRecipe transform;
    private readonly uint sourceWidth;
    private readonly uint sourceHeight;

    private DefectDisplayLocator(
        ImageTransformRecipe transform,
        uint sourceWidth,
        uint sourceHeight,
        int width,
        int height)
    {
        this.transform = transform;
        this.sourceWidth = sourceWidth;
        this.sourceHeight = sourceHeight;
        Width = width;
        Height = height;
    }

    public int Width { get; }

    public int Height { get; }

    /// <summary>
    /// 직접 변환을 준비합니다. 변환을 적용할 수 없으면 <see langword="null"/> 입니다.
    /// </summary>
    public static DefectDisplayLocator? Build(
        LibraryFrameSnapshot frame,
        int width,
        int height)
    {
        ArgumentNullException.ThrowIfNull(frame);
        if (width <= 0 || height <= 0 || frame.SourceMetadata is not { } metadata)
        {
            return null;
        }

        return DevelopDisplayGeometry.TryMapRawToDisplay(
                frame.ImageTransform,
                metadata.PixelWidth,
                metadata.PixelHeight,
                0.0,
                0.0,
                out _,
                out _)
            ? new DefectDisplayLocator(
                frame.ImageTransform,
                metadata.PixelWidth,
                metadata.PixelHeight,
                width,
                height)
            : null;
    }

    /// <summary>
    /// 원본 정규 좌표 한 점이 어느 표시 화소인지 찾습니다. 잘려 나가 보이지 않는 점은
    /// <see langword="false"/> 입니다 — macOS 도 <c>imageFrame.contains</c> 로 걸러 냅니다.
    /// </summary>
    public bool TryLocate(DefectPoint raw, out int x, out int y)
    {
        x = 0;
        y = 0;
        if (!double.IsFinite(raw.X) || !double.IsFinite(raw.Y) ||
            raw.X is < 0.0 or > 1.0 || raw.Y is < 0.0 or > 1.0)
        {
            return false;
        }
        if (!DevelopDisplayGeometry.TryMapRawToDisplay(
                transform,
                sourceWidth,
                sourceHeight,
                raw.X,
                raw.Y,
                out double displayX,
                out double displayY) ||
            !double.IsFinite(displayX) || !double.IsFinite(displayY) ||
            displayX is < 0.0 or > 1.0 || displayY is < 0.0 or > 1.0)
        {
            return false;
        }
        x = Width == 1 ? 0 : (int)Math.Round(displayX * (Width - 1));
        y = Height == 1 ? 0 : (int)Math.Round(displayY * (Height - 1));
        return true;
    }
}
