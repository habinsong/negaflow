using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

/// <summary>
/// 결함 한 종류의 요약입니다. macOS <c>AppModel.DefectClassSummary</c> 와 같습니다 — 화면의
/// 종류별 칩이 이것만 읽습니다.
/// </summary>
public readonly record struct GrainMendClassSummary(
    DefectClassification Classification,
    int Count,
    double MeanConfidence,
    bool AllExcluded);

/// <summary>
/// 자동·가이드 검출 결과를 저장 전에 검토하는 짧은 수명 세션입니다. 검출한 결함을 하나씩 또는
/// 종류째로 포함/제외할 수 있으며, 수락할 때에만 제외한 것을 뺀 region 편집을 만듭니다.
/// </summary>
public sealed class GrainMendReviewSession
{
    /// <summary>
    /// 클릭 관용 반경의 하한입니다. macOS <c>max(3, field.width / 100)</c> 과 같습니다.
    /// </summary>
    private const int MinimumHitRadius = 3;

    private const int HitRadiusDivisor = 100;

    private readonly DefectEditItem source;
    private readonly byte[] rgba;
    private readonly GrainMendComponentMap map;
    private readonly GrainMendMaskWindow window;
    private readonly bool[] excluded;

    /// <summary>검출기가 낸 성분입니다. 분류를 내지 못했으면 비어 있습니다.</summary>
    private readonly IReadOnlyList<DefectPreviewComponent> components;

    private GrainMendReviewSession(
        DefectEditItem source,
        byte[] rgba,
        GrainMendComponentMap map,
        GrainMendMaskWindow window,
        IReadOnlyList<DefectPreviewComponent> components,
        bool falsePositiveRisk)
    {
        this.source = source;
        this.rgba = rgba;
        this.map = map;
        this.window = window;
        this.components = components;
        FalsePositiveRisk = falsePositiveRisk;
        excluded = new bool[map.ComponentCount];
    }

    /// <summary>
    /// macOS <c>DefectLabelField.automaticFalsePositiveRisk</c>. 전체 프레임 자동에서만
    /// 서고, 성분을 하나도 버리지 않습니다 — 캡슐이 개수 대신 경고 문구를 냅니다.
    /// </summary>
    public bool FalsePositiveRisk { get; }

    public int ComponentCount => excluded.Length;

    public int IncludedCount => excluded.Count(value => !value);

    public int ExcludedCount => excluded.Length - IncludedCount;

    /// <summary>검출기가 분류를 냈는지입니다. 내지 못했으면 종류별 칩이 없습니다.</summary>
    public bool IsClassified => components.Count > 0;

    public static GrainMendReviewSession? TryCreate(
        DefectEditItem item,
        bool falsePositiveRisk = false)
    {
        ArgumentNullException.ThrowIfNull(item);
        if (item.RegionMask is not { } mask ||
            GrainMendMaskWindow.For(item) is not { } window ||
            !DefectMaskCodec.TryDecodeRgba8(mask, window.Width, window.Height, out byte[] rgba))
        {
            return null;
        }

        // 검출기 성분이 있으면 그것이 제외 단위입니다 — macOS 와 같이 결함 하나가 하나입니다.
        // 마스크 덩어리로 다시 나누면 붙어 버린 결함 둘이 하나로 보입니다.
        GrainMendComponentMap? seeded = GrainMendComponentMap.Seeded(rgba, window, item.Preview);
        if (seeded is { } byComponent)
        {
            return new GrainMendReviewSession(
                item, rgba, byComponent, window, item.Preview, falsePositiveRisk);
        }
        return GrainMendComponentMap.Blobs(rgba, window.Width, window.Height) is { } byBlob
            ? new GrainMendReviewSession(item, rgba, byBlob, window, [], falsePositiveRisk)
            : null;
    }

    /// <summary>
    /// 화면에서 찍은 자리의 결함을 제외↔포함으로 바꿉니다. 정확히 짚지 않아도 반경 안에서
    /// 가장 가까운 것을 잡습니다 — macOS <c>toggleRegionComponent</c> 와 같습니다.
    /// </summary>
    public bool ToggleAtRaw(DefectPoint rawPoint)
    {
        if (!window.TryLocate(rawPoint, out int x, out int y))
        {
            return false;
        }
        int component = map.NearestOwner(
            x,
            y,
            Math.Max(MinimumHitRadius, window.Width / HitRadiusDivisor));
        if (component < 0 || component >= excluded.Length)
        {
            return false;
        }
        excluded[component] = !excluded[component];
        return true;
    }

    /// <summary>그 성분을 지금 빼고 있는지입니다. 덮개가 성분마다 한 번만 묻습니다.</summary>
    public bool IsComponentExcluded(int component) =>
        component >= 0 && component < excluded.Length && excluded[component];

    /// <summary>원본 정규 좌표 한 점이 제외한 성분에 속하는지입니다.</summary>
    public bool IsExcludedAtRaw(DefectPoint rawPoint) =>
        window.TryLocate(rawPoint, out int x, out int y) &&
        IsComponentExcluded(map.Owner(x, y));

    /// <summary>
    /// 지금 검출 결과의 종류별 요약입니다. macOS <c>defectClassSummaries</c> 와 같이
    /// <see cref="DefectClassification"/> 정의 순서로 내며, 없는 종류는 넣지 않습니다.
    /// </summary>
    public IReadOnlyList<GrainMendClassSummary> ClassSummaries()
    {
        if (components.Count == 0)
        {
            return [];
        }

        int classCount = Enum.GetValues<DefectClassification>().Length;
        int[] counts = new int[classCount];
        double[] confidenceSums = new double[classCount];
        int[] excludedCounts = new int[classCount];
        for (int component = 0; component < components.Count; ++component)
        {
            int index = (int)components[component].Classification;
            if (index < 0 || index >= classCount)
            {
                continue;
            }
            ++counts[index];
            confidenceSums[index] += components[component].Confidence;
            if (IsComponentExcluded(component))
            {
                ++excludedCounts[index];
            }
        }

        List<GrainMendClassSummary> summaries = new(classCount);
        for (int index = 0; index < classCount; ++index)
        {
            if (counts[index] == 0)
            {
                continue;
            }
            summaries.Add(new GrainMendClassSummary(
                (DefectClassification)index,
                counts[index],
                confidenceSums[index] / counts[index],
                excludedCounts[index] == counts[index]));
        }
        return summaries;
    }

    /// <summary>
    /// 한 종류를 통째로 제외↔포함합니다. 하나씩 누른 제외와 같은 목록을 나눠 쓰며, 다시
    /// 검출하지 않습니다 — macOS <c>toggleRegionClass</c> 와 같습니다.
    /// </summary>
    public bool ToggleClass(DefectClassification classification)
    {
        if (components.Count == 0)
        {
            return false;
        }

        bool any = false;
        bool allExcluded = true;
        for (int component = 0; component < components.Count; ++component)
        {
            if (components[component].Classification != classification)
            {
                continue;
            }
            any = true;
            allExcluded &= IsComponentExcluded(component);
        }
        if (!any)
        {
            return false;
        }

        for (int component = 0; component < components.Count && component < excluded.Length; ++component)
        {
            if (components[component].Classification == classification)
            {
                excluded[component] = !allExcluded;
            }
        }
        return true;
    }

    /// <summary>
    /// 남긴 결함만 담은 새 항목입니다. 모두 제외했으면 수락할 것이 없습니다. 이름표의 수와
    /// 분류별 개수·평균 신뢰도는 <b>남은 결함에서 다시 셉니다</b> — macOS
    /// <c>commitRegionDefect</c> 가 생존 성분으로 요약을 다시 만드는 것과 같습니다.
    /// </summary>
    public DefectEditItem? BuildAcceptedEdit()
    {
        if (IncludedCount == 0)
        {
            return null;
        }

        byte[] selected = map.WithoutExcluded(rgba, excluded);
        if (components.Count == 0)
        {
            // 분류가 없습니다. 종류를 지어내지 않고, 검출이 낸 요약을 그대로 둔 채 남은
            // 화소 수만 이름표에 적습니다(원래 이름표와 같은 단위입니다).
            return source with
            {
                Label = new DefectEditLabel(source.Label.Kind, CountMarked(selected)),
                RegionMask = new DefectMask(false, selected),
            };
        }

        List<DefectPreviewComponent> survivors = new(components.Count);
        for (int component = 0; component < components.Count; ++component)
        {
            if (!IsComponentExcluded(component))
            {
                survivors.Add(components[component]);
            }
        }

        return source with
        {
            Label = new DefectEditLabel(source.Label.Kind, survivors.Count),
            Summary = new DefectEditSummary(
                DefectEditSummaryKind.ClassBreakdown,
                Breakdown(survivors)),
            Preview = survivors,
            RegionMask = new DefectMask(false, selected),
        };
    }

    /// <summary>
    /// macOS <c>DefectClassBreakdown(components:)</c> 와 같이 분류 순서로 세고 평균 신뢰도를
    /// 냅니다.
    /// </summary>
    private static DefectClassBreakdown Breakdown(
        IReadOnlyList<DefectPreviewComponent> survivors)
    {
        DefectClassCount[] counts = [.. survivors
            .GroupBy(component => component.Classification)
            .OrderBy(group => group.Key)
            .Select(group => new DefectClassCount(group.Key, group.Count()))];
        return new DefectClassBreakdown(
            counts,
            survivors.Average(component => component.Confidence));
    }

    private static int CountMarked(byte[] rgba)
    {
        int marked = 0;
        for (int pixel = 0; pixel * 4 < rgba.Length; ++pixel)
        {
            if (rgba[pixel * 4] != 0)
            {
                ++marked;
            }
        }
        return marked;
    }
}
