using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

/// <summary>
/// 자동·가이드 검출 결과를 저장 전에 검토하는 짧은 수명 세션입니다. 검출 마스크의 연결 성분을
/// 각각 포함/제외할 수 있으며, 수락할 때에만 제외 성분을 뺀 region 편집을 만듭니다.
/// </summary>
public sealed class GrainMendReviewSession
{
    private const byte MarkedThreshold = 8;

    private readonly DefectEditItem source;
    private readonly byte[] rgba;
    private readonly int[] componentByPixel;
    private readonly bool[] excluded;
    private readonly int width;
    private readonly int height;
    private readonly DefectRect roi;
    private readonly DefectSize baseSize;

    private GrainMendReviewSession(
        DefectEditItem source,
        byte[] rgba,
        int[] componentByPixel,
        int componentCount,
        int width,
        int height,
        DefectRect roi,
        DefectSize baseSize)
    {
        this.source = source;
        this.rgba = rgba;
        this.componentByPixel = componentByPixel;
        excluded = new bool[componentCount];
        this.width = width;
        this.height = height;
        this.roi = roi;
        this.baseSize = baseSize;
    }

    public int ComponentCount => excluded.Length;

    public int IncludedCount => excluded.Count(value => !value);

    public int ExcludedCount => excluded.Length - IncludedCount;

    public static GrainMendReviewSession? TryCreate(DefectEditItem item)
    {
        ArgumentNullException.ThrowIfNull(item);
        if (item.RegionMask is not { } mask || item.RegionRoi is not { } roi ||
            item.RegionWidth is not { } width || item.RegionHeight is not { } height ||
            item.BaseSize is not { } baseSize || width <= 0 || height <= 0 ||
            !DefectMaskCodec.TryDecodeRgba8(mask, width, height, out byte[] rgba))
        {
            return null;
        }

        int[] labels = Enumerable.Repeat(-1, checked(width * height)).ToArray();
        int[] queue = new int[labels.Length];
        int componentCount = 0;
        for (int index = 0; index < labels.Length; ++index)
        {
            if (labels[index] != -1 || rgba[index * 4] <= MarkedThreshold)
            {
                continue;
            }

            int head = 0;
            int tail = 0;
            queue[tail++] = index;
            labels[index] = componentCount;
            while (head < tail)
            {
                int current = queue[head++];
                int x = current % width;
                int y = current / width;
                for (int offsetY = -1; offsetY <= 1; ++offsetY)
                {
                    for (int offsetX = -1; offsetX <= 1; ++offsetX)
                    {
                        if (offsetX == 0 && offsetY == 0)
                        {
                            continue;
                        }
                        int nextX = x + offsetX;
                        int nextY = y + offsetY;
                        if (nextX < 0 || nextX >= width || nextY < 0 || nextY >= height)
                        {
                            continue;
                        }
                        int next = (nextY * width) + nextX;
                        if (labels[next] != -1 || rgba[next * 4] <= MarkedThreshold)
                        {
                            continue;
                        }
                        labels[next] = componentCount;
                        queue[tail++] = next;
                    }
                }
            }
            ++componentCount;
        }

        return componentCount == 0
            ? null
            : new GrainMendReviewSession(
                item, rgba, labels, componentCount, width, height, roi, baseSize);
    }

    public bool ToggleAtRaw(DefectPoint rawPoint)
    {
        if (!TryGetComponent(rawPoint, out int component))
        {
            return false;
        }
        excluded[component] = !excluded[component];
        return true;
    }

    public bool IsExcludedAtRaw(DefectPoint rawPoint) =>
        TryGetComponent(rawPoint, out int component) && excluded[component];

    /// <summary>선택된 component만 남긴 새 item입니다. 모두 제외했으면 수락할 것이 없습니다.</summary>
    public DefectEditItem? BuildAcceptedEdit()
    {
        int included = IncludedCount;
        if (included == 0)
        {
            return null;
        }

        byte[] selected = (byte[])rgba.Clone();
        for (int pixel = 0; pixel < componentByPixel.Length; ++pixel)
        {
            int component = componentByPixel[pixel];
            if (component < 0 || !excluded[component])
            {
                continue;
            }
            int offset = pixel * 4;
            selected[offset] = 0;
            selected[offset + 1] = 0;
            selected[offset + 2] = 0;
            selected[offset + 3] = 0;
        }

        return source with
        {
            Label = new DefectEditLabel(source.Label.Kind, included),
            Summary = new DefectEditSummary(
                DefectEditSummaryKind.ClassBreakdown,
                new DefectClassBreakdown(
                    [new DefectClassCount(DefectClassification.Dust, included)],
                    1.0)),
            RegionMask = new DefectMask(false, selected),
        };
    }

    private bool TryGetComponent(DefectPoint rawPoint, out int component)
    {
        component = -1;
        if (!double.IsFinite(rawPoint.X) || !double.IsFinite(rawPoint.Y) ||
            rawPoint.X < 0.0 || rawPoint.X > 1.0 || rawPoint.Y < 0.0 || rawPoint.Y > 1.0 ||
            baseSize.Width <= 1.0 || baseSize.Height <= 1.0)
        {
            return false;
        }

        // Raw points are normalized top-first while recipe ROI is y-up; bitmap rows stay
        // top-first, so convert the ROI origin once before indexing its mask.
        double rawTop = baseSize.Height - roi.Y - roi.Height;
        int localX = (int)Math.Round((rawPoint.X * (baseSize.Width - 1.0)) - roi.X);
        int localY = (int)Math.Round((rawPoint.Y * (baseSize.Height - 1.0)) - rawTop);
        if (localX < 0 || localX >= width || localY < 0 || localY >= height)
        {
            return false;
        }
        component = componentByPixel[(localY * width) + localX];
        return component >= 0;
    }
}
