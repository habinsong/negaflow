using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

/// <summary>
/// 마스크 화소를 검출 성분에 나눠 준 표입니다. macOS <c>DefectLabelField.labels</c> 와 같은
/// 자리이며, 클릭 한 번이 어느 결함을 가리키는지와 제외한 결함이 어느 화소를 놓아야 하는지를
/// 이 표 하나로 답합니다.
/// </summary>
/// <remarks>
/// <para>
/// macOS 는 마스크를 성분에서 <b>그려 내므로</b> 화소와 성분이 처음부터 이어져 있습니다.
/// Windows 는 네이티브가 마스크 한 장과 성분 목록을 따로 주고, 마스크는 원본 해상도로 다시
/// 표본을 뜬 것입니다. 그래서 성분의 미리보기 점을 <b>씨앗</b>으로 놓고 마스크를 따라 퍼뜨려
/// 같은 관계를 복원합니다 — 성분 두 개가 한 덩어리로 붙어 버려도 각자의 화소를 가집니다.
/// </para>
/// <para>
/// 씨앗이 하나도 닿지 않은 덩어리는 임자 없이 남깁니다. 임자 없는 화소는 제외할 수 없으므로
/// 언제나 복원에 들어갑니다 — 검출이 찾은 증거를 조용히 버리지 않습니다.
/// </para>
/// </remarks>
public sealed class GrainMendComponentMap
{
    /// <summary>어느 성분도 가지지 않은 화소입니다.</summary>
    public const int Unowned = -1;

    /// <summary>
    /// 씨앗이 표본 오차로 덩어리 밖에 떨어질 때 훑는 반경입니다. 마스크는 검출 해상도에서
    /// 원본 해상도로 다시 뜬 것이라 경계가 한 화소쯤 움직일 수 있습니다.
    /// </summary>
    private const int SeedSearchRadius = 1;

    private readonly int[] ownerByPixel;
    private readonly int width;
    private readonly int height;

    private GrainMendComponentMap(int[] ownerByPixel, int width, int height, int componentCount)
    {
        this.ownerByPixel = ownerByPixel;
        this.width = width;
        this.height = height;
        ComponentCount = componentCount;
    }

    public int ComponentCount { get; }

    /// <summary>
    /// 검출기가 낸 성분으로 나눕니다. 성분의 미리보기 점에서 시작해 마스크를 따라 8방향으로
    /// 퍼뜨립니다 — 먼저 닿은 성분이 그 화소의 임자입니다(씨앗까지의 거리가 같으면 성분 순서).
    /// </summary>
    /// <returns>씨앗이 하나도 마스크에 닿지 못하면 <see langword="null"/> 입니다.</returns>
    public static GrainMendComponentMap? Seeded(
        byte[] rgba,
        GrainMendMaskWindow window,
        IReadOnlyList<DefectPreviewComponent> preview)
    {
        ArgumentNullException.ThrowIfNull(rgba);
        ArgumentNullException.ThrowIfNull(preview);
        if (!window.IsValid || preview.Count == 0)
        {
            return null;
        }

        int width = window.Width;
        int height = window.Height;
        int pixelCount = checked(width * height);
        if (rgba.Length < checked(pixelCount * 4))
        {
            return null;
        }

        int[] owner = NewOwnerMap(pixelCount);
        // 대기열은 마스크에 실제로 표시된 화소 수만큼이면 충분합니다. 화소 전부로 잡으면
        // 전체 프레임 자동 검출에서 수십 MB 를 쓸데없이 붙듭니다.
        int[] queue = new int[CountMarked(rgba, pixelCount)];
        if (queue.Length == 0)
        {
            return null;
        }

        int tail = 0;
        for (int component = 0; component < preview.Count; ++component)
        {
            foreach (DefectPoint point in preview[component].Points)
            {
                if (window.TryLocate(point, out int x, out int y) &&
                    TryPlaceSeed(rgba, owner, width, height, x, y, component, out int seed))
                {
                    queue[tail++] = seed;
                }
            }
        }
        if (tail == 0)
        {
            return null;
        }

        Spread(rgba, owner, queue, tail, width, height);
        return new GrainMendComponentMap(owner, width, height, preview.Count);
    }

    /// <summary>
    /// 검출기가 성분을 내지 못했을 때의 물러섬입니다. 연결된 덩어리 하나가 성분 하나이며,
    /// 분류는 없습니다 — 종류를 지어내지 않습니다.
    /// </summary>
    public static GrainMendComponentMap? Blobs(byte[] rgba, int width, int height)
    {
        ArgumentNullException.ThrowIfNull(rgba);
        int pixelCount = checked(width * height);
        if (width <= 0 || height <= 0 || rgba.Length < checked(pixelCount * 4))
        {
            return null;
        }

        int[] owner = NewOwnerMap(pixelCount);
        int marked = CountMarked(rgba, pixelCount);
        if (marked == 0)
        {
            return null;
        }

        int[] queue = new int[marked];
        int componentCount = 0;
        for (int index = 0; index < pixelCount; ++index)
        {
            if (owner[index] != Unowned || rgba[index * 4] == 0)
            {
                continue;
            }
            owner[index] = componentCount;
            queue[0] = index;
            Spread(rgba, owner, queue, 1, width, height);
            ++componentCount;
        }
        return componentCount == 0
            ? null
            : new GrainMendComponentMap(owner, width, height, componentCount);
    }

    /// <summary>그 자리의 성분입니다. 임자가 없으면 <see cref="Unowned"/> 입니다.</summary>
    public int Owner(int x, int y) =>
        x < 0 || x >= width || y < 0 || y >= height
            ? Unowned
            : ownerByPixel[(y * width) + x];

    /// <summary>
    /// 정확한 자리를 먼저 보고, 없으면 반경 안에서 가장 가까운 성분을 찾습니다. macOS
    /// <c>DefectLabelField.nearestComponentID(atX:y:radius:)</c> 와 같은 정사각 링 확장이며,
    /// 얇은 스크래치처럼 클릭 표적이 작을 때 관용도를 줍니다.
    /// </summary>
    public int NearestOwner(int x, int y, int radius)
    {
        int exact = Owner(x, y);
        if (exact != Unowned)
        {
            return exact;
        }
        for (int ring = 1; ring <= radius; ++ring)
        {
            int best = Unowned;
            for (int offsetY = -ring; offsetY <= ring; ++offsetY)
            {
                for (int offsetX = -ring; offsetX <= ring; ++offsetX)
                {
                    if (Math.Max(Math.Abs(offsetX), Math.Abs(offsetY)) != ring)
                    {
                        continue;
                    }
                    int found = Owner(x + offsetX, y + offsetY);
                    if (found != Unowned)
                    {
                        best = found;
                    }
                }
            }
            if (best != Unowned)
            {
                return best;
            }
        }
        return Unowned;
    }

    /// <summary>제외한 성분의 화소를 지운 마스크 사본입니다.</summary>
    public byte[] WithoutExcluded(byte[] rgba, ReadOnlySpan<bool> excluded)
    {
        ArgumentNullException.ThrowIfNull(rgba);
        byte[] selected = (byte[])rgba.Clone();
        for (int pixel = 0; pixel < ownerByPixel.Length; ++pixel)
        {
            int component = ownerByPixel[pixel];
            if (component < 0 || component >= excluded.Length || !excluded[component])
            {
                continue;
            }
            int offset = pixel * 4;
            selected[offset] = 0;
            selected[offset + 1] = 0;
            selected[offset + 2] = 0;
            selected[offset + 3] = 0;
        }
        return selected;
    }

    private static int[] NewOwnerMap(int pixelCount)
    {
        int[] owner = new int[pixelCount];
        Array.Fill(owner, Unowned);
        return owner;
    }

    private static int CountMarked(byte[] rgba, int pixelCount)
    {
        int marked = 0;
        for (int pixel = 0; pixel < pixelCount; ++pixel)
        {
            if (rgba[pixel * 4] != 0)
            {
                ++marked;
            }
        }
        return marked;
    }

    /// <summary>
    /// 씨앗 한 알을 놓습니다. 다시 뜬 마스크의 경계가 한 화소쯤 움직여 점이 덩어리 밖에
    /// 떨어졌으면 바로 옆 칸까지만 봅니다.
    /// </summary>
    private static bool TryPlaceSeed(
        byte[] rgba,
        int[] owner,
        int width,
        int height,
        int x,
        int y,
        int component,
        out int seed)
    {
        seed = 0;
        for (int radius = 0; radius <= SeedSearchRadius; ++radius)
        {
            for (int offsetY = -radius; offsetY <= radius; ++offsetY)
            {
                for (int offsetX = -radius; offsetX <= radius; ++offsetX)
                {
                    if (Math.Max(Math.Abs(offsetX), Math.Abs(offsetY)) != radius)
                    {
                        continue;
                    }
                    int nextX = x + offsetX;
                    int nextY = y + offsetY;
                    if (nextX < 0 || nextX >= width || nextY < 0 || nextY >= height)
                    {
                        continue;
                    }
                    int index = (nextY * width) + nextX;
                    if (rgba[index * 4] == 0 || owner[index] != Unowned)
                    {
                        continue;
                    }
                    owner[index] = component;
                    seed = index;
                    return true;
                }
            }
        }
        return false;
    }

    /// <summary>
    /// 이미 임자가 정해진 씨앗들에서 8방향으로 퍼집니다. 너비 우선이므로 씨앗까지의 칸 수가
    /// 적은 성분이 그 화소를 가집니다.
    /// </summary>
    private static void Spread(
        byte[] rgba,
        int[] owner,
        int[] queue,
        int tail,
        int width,
        int height)
    {
        int head = 0;
        while (head < tail)
        {
            int current = queue[head++];
            int component = owner[current];
            int x = current % width;
            int y = current / width;
            for (int offsetY = -1; offsetY <= 1; ++offsetY)
            {
                int nextY = y + offsetY;
                if (nextY < 0 || nextY >= height)
                {
                    continue;
                }
                for (int offsetX = -1; offsetX <= 1; ++offsetX)
                {
                    int nextX = x + offsetX;
                    if ((offsetX == 0 && offsetY == 0) || nextX < 0 || nextX >= width)
                    {
                        continue;
                    }
                    int next = (nextY * width) + nextX;
                    if (owner[next] != Unowned || rgba[next * 4] == 0)
                    {
                        continue;
                    }
                    owner[next] = component;
                    queue[tail++] = next;
                }
            }
        }
    }
}
