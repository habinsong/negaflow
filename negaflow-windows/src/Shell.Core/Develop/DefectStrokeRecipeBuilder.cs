using Negaflow.Catalog;

namespace Negaflow.Shell;

/// <summary>
/// 캔버스에서 그은 획 하나를 결함 recipe 항목으로 만듭니다.
/// </summary>
/// <remarks>
/// <para>
/// 좌표는 이미 <see cref="DevelopDisplayGeometry"/> 가 원본 공간으로 되돌린 값이어야 합니다.
/// 이 자리에서는 공간을 바꾸지 않습니다 — 두 곳에서 변환하면 언젠가 한쪽만 고쳐집니다.
/// </para>
/// <para>
/// 굵기와 지름은 <b>짧은 변에 대한 비율</b>입니다(<c>defect_heal_brush.h</c>,
/// <c>defect_clone_stamp.h</c>). 화면 화소가 아니라 원본 기준이라 확대해서 칠해도 같은 굵기가
/// 나옵니다.
/// </para>
/// </remarks>
public static class DefectStrokeRecipeBuilder
{
    /// <summary>
    /// 한 획을 담은 새 recipe 입니다. 기존 항목은 그대로 두고 뒤에 붙이며, 개정 번호를 하나
    /// 올립니다. 원본 identity 가 다른 recipe 에는 붙이지 않습니다 — 다른 사진의 편집을
    /// 이어받으면 엉뚱한 자리를 지웁니다.
    /// </summary>
    public static DefectRecipeSnapshot? AppendBrushStroke(
        Guid frameId,
        DefectSourceIdentity sourceIdentity,
        DefectRecipeSnapshot? existing,
        IReadOnlyList<DefectPoint> rawPoints,
        double thickness,
        DefectSize baseSize) =>
        Append(
            frameId,
            sourceIdentity,
            existing,
            rawPoints,
            thickness,
            baseSize,
            static (points, size) => new DefectEditItem(
                Guid.NewGuid(),
                DefectEditKind.Brush,
                Enabled: true,
                Strength: 1.0,
                new DefectEditLabel(DefectEditLabelKind.Brush, 1),
                new DefectEditSummary(DefectEditSummaryKind.Brush, null),
                size,
                [])
            {
                Strokes = [new DefectStroke(points.Points, points.Size)],
            });

    /// <summary>
    /// 복제 도장 한 획입니다. <paramref name="offsetX"/> 와 <paramref name="offsetY"/> 는 대상에서
    /// 원본을 가리키는 변위이며 원본 이미지의 정규 좌표 단위입니다.
    /// </summary>
    public static DefectRecipeSnapshot? AppendCloneStroke(
        Guid frameId,
        DefectSourceIdentity sourceIdentity,
        DefectRecipeSnapshot? existing,
        IReadOnlyList<DefectPoint> rawPoints,
        double diameter,
        double offsetX,
        double offsetY,
        DefectSize baseSize,
        double hardness = DefaultCloneHardness)
    {
        if (!double.IsFinite(offsetX) || !double.IsFinite(offsetY) ||
            !double.IsFinite(hardness) || hardness is < 0.0 or > 1.0 ||
            (offsetX == 0.0 && offsetY == 0.0))
        {
            // 변위가 없으면 자기 자신을 복제합니다 — 아무 일도 일어나지 않는 편집을
            // 카탈로그에 남기지 않습니다.
            return null;
        }
        return Append(
            frameId,
            sourceIdentity,
            existing,
            rawPoints,
            diameter,
            baseSize,
            (points, size) => new DefectEditItem(
                Guid.NewGuid(),
                DefectEditKind.Clone,
                Enabled: true,
                Strength: 1.0,
                new DefectEditLabel(DefectEditLabelKind.Clone, 1),
                new DefectEditSummary(DefectEditSummaryKind.Clone, null),
                size,
                [])
            {
                CloneStrokes =
                [
                    new DefectCloneStroke(points.Points, offsetX, offsetY, points.Size, hardness),
                ],
            });
    }

    /// <summary>macOS 복제 도장의 가장자리 부드러움 기본값입니다.</summary>
    public const double DefaultCloneHardness = 0.5;

    /// <summary>
    /// 붙어 있는 점은 버립니다. 포인터는 한 획에 수백 개를 흘리는데 그대로 담으면 recipe 가
    /// 커지고 수리 결과는 달라지지 않습니다.
    /// </summary>
    private const double MinimumPointSpacing = 1.0e-4;

    private readonly record struct Stroke(IReadOnlyList<DefectPoint> Points, double Size);

    private static DefectRecipeSnapshot? Append(
        Guid frameId,
        DefectSourceIdentity sourceIdentity,
        DefectRecipeSnapshot? existing,
        IReadOnlyList<DefectPoint> rawPoints,
        double size,
        DefectSize baseSize,
        Func<Stroke, DefectSize?, DefectEditItem> makeItem)
    {
        ArgumentNullException.ThrowIfNull(rawPoints);
        ArgumentNullException.ThrowIfNull(makeItem);
        if (!double.IsFinite(size) || size <= 0.0)
        {
            return null;
        }
        if (existing?.SourceIdentity is { } identity && identity != sourceIdentity)
        {
            return null;
        }

        List<DefectPoint> points = Thin(rawPoints);
        if (points.Count == 0)
        {
            return null;
        }

        DefectEditItem item = makeItem(new Stroke(points, size), baseSize);
        DefectEditItem[] items = existing is null ? [item] : [.. existing.Items, item];
        try
        {
            return DefectRecipeSnapshot.Create(
                frameId,
                checked((existing?.RecipeRevision ?? 0UL) + 1UL),
                sourceIdentity,
                items);
        }
        catch (Exception error) when (error is ArgumentException or OverflowException)
        {
            return null;
        }
    }

    private static List<DefectPoint> Thin(IReadOnlyList<DefectPoint> rawPoints)
    {
        List<DefectPoint> points = [];
        foreach (DefectPoint point in rawPoints)
        {
            if (!double.IsFinite(point.X) || !double.IsFinite(point.Y) ||
                point.X is < 0.0 or > 1.0 || point.Y is < 0.0 or > 1.0)
            {
                continue;
            }
            if (points.Count != 0)
            {
                DefectPoint last = points[^1];
                if (Math.Abs(point.X - last.X) < MinimumPointSpacing &&
                    Math.Abs(point.Y - last.Y) < MinimumPointSpacing)
                {
                    continue;
                }
            }
            points.Add(point);
        }
        return points;
    }
}
