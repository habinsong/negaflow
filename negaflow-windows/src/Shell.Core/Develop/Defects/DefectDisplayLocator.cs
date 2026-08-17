using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

/// <summary>
/// 원본 정규 좌표를 표시 화소로 되돌리는 표입니다.
/// </summary>
/// <remarks>
/// <para>
/// <see cref="DevelopDisplayGeometry"/> 는 표시 → 원본 한 방향만 있습니다. 그 식을 손으로
/// 뒤집으면 회전·수평보정·크롭 세 단계를 다시 유도해야 하고, 두 벌이 되면 언젠가 한쪽만
/// 고쳐집니다. 그래서 뒤집지 않고, 표시 화소를 한 번 훑으면서 원본 격자에 그 화소를 적어 둡니다.
/// </para>
/// <para>
/// 격자는 원본 정규 좌표를 <see cref="Resolution"/> 칸으로 나눈 것입니다. 같은 칸에 여러 표시
/// 화소가 들어오면 나중 것이 덮어씁니다 — 어느 쪽이든 그 칸 안의 화소이므로 한 화소 차이입니다.
/// </para>
/// </remarks>
public sealed class DefectDisplayLocator
{
    /// <summary>원본 정규 좌표의 칸 수입니다. 표시 크기와 무관하게 고정입니다.</summary>
    public const int Resolution = 1024;

    private const int Empty = -1;

    private readonly int[] cells;

    private DefectDisplayLocator(int[] cells, int width, int height)
    {
        this.cells = cells;
        Width = width;
        Height = height;
    }

    public int Width { get; }

    public int Height { get; }

    /// <summary>
    /// 표시 크기 한 장을 훑어 표를 만듭니다. 변환을 적용할 수 없으면 <see langword="null"/> 입니다.
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

        int[] cells = new int[Resolution * Resolution];
        Array.Fill(cells, Empty);
        bool any = false;
        for (int y = 0; y < height; ++y)
        {
            double displayY = height == 1 ? 0.0 : (double)y / (height - 1);
            for (int x = 0; x < width; ++x)
            {
                double displayX = width == 1 ? 0.0 : (double)x / (width - 1);
                if (!DevelopDisplayGeometry.TryMapDisplayToRaw(
                        frame.ImageTransform,
                        metadata.PixelWidth,
                        metadata.PixelHeight,
                        displayX,
                        displayY,
                        out double rawX,
                        out double rawY))
                {
                    continue;
                }
                cells[Cell(rawX, rawY)] = (y * width) + x;
                any = true;
            }
        }
        return any ? new DefectDisplayLocator(cells, width, height) : null;
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
        int index = cells[Cell(raw.X, raw.Y)];
        if (index == Empty)
        {
            return false;
        }
        x = index % Width;
        y = index / Width;
        return true;
    }

    private static int Cell(double rawX, double rawY)
    {
        int column = Math.Clamp((int)(rawX * (Resolution - 1)), 0, Resolution - 1);
        int row = Math.Clamp((int)(rawY * (Resolution - 1)), 0, Resolution - 1);
        return (row * Resolution) + column;
    }
}
