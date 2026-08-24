using Negaflow.Catalog;

namespace Negaflow.Shell;

/// <summary>
/// 캔버스에서 그은 획 하나를 결함 recipe 항목으로 만듭니다.
/// </summary>
/// <remarks>
/// <para>
/// 좌표는 이미 <see cref="Negaflow.Shell.Develop.DevelopDefectEditor"/> 가 원본 공간으로 되돌린 값이어야 합니다.
/// 이 자리에서는 공간을 바꾸지 않습니다 — 두 곳에서 변환하면 언젠가 한쪽만 고쳐집니다.
/// </para>
/// <para>
/// 브러시 굵기는 짧은 변에 대한 비율이고, 복제 도장 지름은 macOS와 같은 원본 raw 화소
/// 단위입니다. 서로 다른 단위를 섞으면 48px 복제 도장이 0.01px로 축소되어 사실상 보이지
/// 않습니다.
/// </para>
/// </remarks>
public static class DefectStrokeRecipeBuilder
{
    public static DefectRecipeSnapshot? AppendBrushStroke(
        Guid frameId,
        DefectSourceIdentity sourceIdentity,
        DefectRecipeSnapshot? existing,
        IReadOnlyList<DefectPoint> rawPoints,
        double thickness,
        DefectSize baseSize) => AppendBrushStrokes(
            frameId,
            sourceIdentity,
            existing,
            [new DefectStroke(rawPoints, thickness)],
            baseSize);

    /// <summary>macOS처럼 한 번 적용한 여러 Brush 획을 한 item과 한 revision에 담습니다.</summary>
    public static DefectRecipeSnapshot? AppendBrushStrokes(
        Guid frameId,
        DefectSourceIdentity sourceIdentity,
        DefectRecipeSnapshot? existing,
        IReadOnlyList<DefectStroke> rawStrokes,
        DefectSize baseSize)
    {
        ArgumentNullException.ThrowIfNull(rawStrokes);
        if (rawStrokes.Count == 0)
        {
            return null;
        }
        List<DefectStroke> strokes = new(rawStrokes.Count);
        foreach (DefectStroke stroke in rawStrokes)
        {
            if (!double.IsFinite(stroke.Thickness) || stroke.Thickness <= 0.0 ||
                !TryCopyPoints(stroke.Points, out DefectPoint[] points))
            {
                return null;
            }
            strokes.Add(new DefectStroke(points, stroke.Thickness));
        }
        try
        {
            DefectEditItem item = new(
                Guid.NewGuid(),
                DefectEditKind.Brush,
                Enabled: true,
                Strength: 1.0,
                new DefectEditLabel(DefectEditLabelKind.Brush, strokes.Count),
                new DefectEditSummary(DefectEditSummaryKind.Brush, null),
                baseSize,
                [])
            {
                Strokes = strokes,
            };
            return AppendItem(frameId, sourceIdentity, existing, item);
        }
        catch (Exception error) when (error is ArgumentException or OverflowException)
        {
            return null;
        }
    }

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
            !double.IsFinite(diameter) || diameter <= 0.0 ||
            !double.IsFinite(hardness) || hardness is < 0.0 or > 1.0 ||
            !TryCopyPoints(rawPoints, out DefectPoint[] points))
        {
            return null;
        }
        try
        {
            DefectEditItem item = new(
                Guid.NewGuid(),
                DefectEditKind.Clone,
                Enabled: true,
                Strength: 1.0,
                new DefectEditLabel(
                    DefectEditLabelKind.Clone,
                    (int)Math.Clamp(Math.Truncate(diameter), 0.0, int.MaxValue)),
                new DefectEditSummary(DefectEditSummaryKind.Clone, null),
                baseSize,
                [])
            {
                CloneStrokes =
                [
                    new DefectCloneStroke(points, offsetX, offsetY, diameter, hardness),
                ],
            };
            return AppendItem(frameId, sourceIdentity, existing, item);
        }
        catch (Exception error) when (error is ArgumentException or OverflowException)
        {
            return null;
        }
    }

    /// <summary>macOS 복제 도장의 가장자리 부드러움 기본값입니다.</summary>
    public const double DefaultCloneHardness = 0.5;

    private static DefectRecipeSnapshot? AppendItem(
        Guid frameId,
        DefectSourceIdentity sourceIdentity,
        DefectRecipeSnapshot? existing,
        DefectEditItem item)
    {
        if (existing?.SourceIdentity is { } identity && identity != sourceIdentity)
        {
            return null;
        }
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

    private static bool TryCopyPoints(
        IReadOnlyList<DefectPoint> rawPoints,
        out DefectPoint[] points)
    {
        ArgumentNullException.ThrowIfNull(rawPoints);
        points = new DefectPoint[rawPoints.Count];
        if (points.Length == 0)
        {
            return false;
        }
        for (int index = 0; index < rawPoints.Count; index++)
        {
            DefectPoint point = rawPoints[index];
            if (!double.IsFinite(point.X) || !double.IsFinite(point.Y) ||
                point.X is < 0.0 or > 1.0 || point.Y is < 0.0 or > 1.0)
            {
                points = [];
                return false;
            }
            points[index] = point;
        }
        return true;
    }
}
