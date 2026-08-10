using System.Runtime.CompilerServices;
using Negaflow.Catalog;
using Negaflow.Interop;

namespace Negaflow.Shell;

internal static class DefectRecipeProjector
{
    private const int MaximumNativeRegionEdits = 4_096;
    private static readonly ConditionalWeakTable<
        DefectRecipeSnapshot,
        Projection> Cache = new();

    public static bool TryProject(
        DefectRecipeSnapshot? recipe,
        out IReadOnlyList<DevelopDefectRegionEdit> regions,
        out IReadOnlyList<DevelopDefectCloneEdit> clones,
        out IReadOnlyList<DevelopDefectBrushEdit> brushes,
        out IReadOnlyList<DevelopDefectRecipeEditRef> order,
        out DevelopRequestRefusal refusal)
    {
        if (recipe is null)
        {
            regions = [];
            clones = [];
            brushes = [];
            order = [];
            refusal = DevelopRequestRefusal.None;
            return true;
        }

        Projection projection = Cache.GetValue(recipe, Project);
        regions = projection.Regions;
        clones = projection.Clones;
        brushes = projection.Brushes;
        order = projection.Order;
        refusal = projection.Refusal;
        return refusal == DevelopRequestRefusal.None;
    }

    private static Projection Project(DefectRecipeSnapshot recipe)
    {
        List<DevelopDefectRegionEdit> regions = [];
        List<DevelopDefectCloneEdit> clones = [];
        List<DevelopDefectBrushEdit> brushes = [];
        List<DevelopDefectRecipeEditRef> order = [];
        foreach (DefectEditItem item in recipe.Items)
        {
            if (!item.Enabled)
            {
                continue;
            }
            switch (item.Kind)
            {
                case DefectEditKind.Region:
                    if (item.RegionMask is not { } mask ||
                        item.RegionRoi is not { } roi ||
                        item.RegionWidth is not { } width ||
                        item.RegionHeight is not { } height ||
                        !TryAppendRegion(
                            regions,
                            mask,
                            roi,
                            width,
                            height,
                            item.Strength))
                    {
                        return Projection.Invalid();
                    }
                    order.Add(new(
                        DevelopDefectEditKind.Region,
                        checked((uint)regions.Count - 1U)));
                    break;
                case DefectEditKind.Infrared:
                    foreach (DefectCluster cluster in item.Clusters ?? [])
                    {
                        if (!TryAppendRegion(
                                regions,
                                cluster.Mask,
                                cluster.Roi,
                                cluster.Width,
                                cluster.Height,
                                item.Strength))
                        {
                            return Projection.Invalid();
                        }
                        order.Add(new(
                            DevelopDefectEditKind.Region,
                            checked((uint)regions.Count - 1U)));
                    }
                    break;
                case DefectEditKind.Brush:
                    if (!TryAppendBrush(brushes, item.Strokes, item.Strength))
                    {
                        return Projection.Invalid();
                    }
                    order.Add(new(
                        DevelopDefectEditKind.Brush,
                        checked((uint)brushes.Count - 1U)));
                    break;
                case DefectEditKind.Clone:
                    if (!TryAppendClone(clones, item.CloneStrokes, item.Strength))
                    {
                        return Projection.Invalid();
                    }
                    order.Add(new(
                        DevelopDefectEditKind.Clone,
                        checked((uint)clones.Count - 1U)));
                    break;
                default:
                    return Projection.Invalid();
            }
        }
        return new Projection(
            regions.ToArray(),
            clones.ToArray(),
            brushes.ToArray(),
            order.ToArray(),
            DevelopRequestRefusal.None);
    }

    private static bool TryAppendBrush(
        List<DevelopDefectBrushEdit> brushes,
        IReadOnlyList<DefectStroke>? source,
        double strength)
    {
        if (source is null || brushes.Count >= 4_096)
        {
            return false;
        }
        DevelopDefectBrushStroke[] strokes = new DevelopDefectBrushStroke[source.Count];
        for (int index = 0; index < strokes.Length; ++index)
        {
            DefectStroke stroke = source[index];
            if (!double.IsFinite(stroke.Thickness) ||
                stroke.Thickness is < 0 or > 1 ||
                stroke.Points.Any(point =>
                    !double.IsFinite(point.X) || !double.IsFinite(point.Y) ||
                    point.X is < 0 or > 1 || point.Y is < 0 or > 1))
            {
                return false;
            }
            strokes[index] = new DevelopDefectBrushStroke
            {
                Points = stroke.Points.Select(point =>
                    new DevelopDefectBrushPoint(point.X, point.Y)).ToArray(),
                Thickness = stroke.Thickness,
            };
        }
        brushes.Add(new DevelopDefectBrushEdit
        {
            IsEnabled = true,
            Strength = strength,
            Strokes = strokes,
        });
        return true;
    }

    private static bool TryAppendClone(
        List<DevelopDefectCloneEdit> clones,
        IReadOnlyList<DefectCloneStroke>? source,
        double strength)
    {
        if (source is null || clones.Count >= 4_096)
        {
            return false;
        }
        DevelopDefectCloneStroke[] strokes = new DevelopDefectCloneStroke[source.Count];
        for (int index = 0; index < strokes.Length; ++index)
        {
            DefectCloneStroke stroke = source[index];
            strokes[index] = new DevelopDefectCloneStroke
            {
                Points = stroke.Points.Select(point =>
                    new DevelopDefectClonePoint(point.X, point.Y)).ToArray(),
                OffsetX = stroke.OffsetX,
                OffsetY = stroke.OffsetY,
                DiameterPixels = stroke.Diameter,
                Hardness = stroke.Hardness,
            };
        }
        clones.Add(new DevelopDefectCloneEdit
        {
            IsEnabled = true,
            Strength = strength,
            Strokes = strokes,
        });
        return true;
    }

    private static bool TryAppendRegion(
        List<DevelopDefectRegionEdit> regions,
        DefectMask mask,
        DefectRect roi,
        int width,
        int height,
        double strength)
    {
        if (regions.Count >= MaximumNativeRegionEdits ||
            width <= 0 || height <= 0 ||
            roi.X < 0 || roi.Y < 0 ||
            roi.Width != width || roi.Height != height ||
            roi.X != Math.Truncate(roi.X) || roi.Y != Math.Truncate(roi.Y) ||
            roi.X > uint.MaxValue || roi.Y > uint.MaxValue ||
            width > uint.MaxValue / 4 ||
            !DefectMaskCodec.TryDecodeRgba8(mask, width, height, out byte[] data))
        {
            return false;
        }

        regions.Add(new DevelopDefectRegionEdit
        {
            IsEnabled = true,
            RoiX = (uint)roi.X,
            RoiY = (uint)roi.Y,
            Width = (uint)width,
            Height = (uint)height,
            MaskStrideBytes = (uint)width * 4,
            Mask = data,
            Strength = strength,
            PreferredAngleDegrees = null,
        });
        return true;
    }

    private sealed record Projection(
        IReadOnlyList<DevelopDefectRegionEdit> Regions,
        IReadOnlyList<DevelopDefectCloneEdit> Clones,
        IReadOnlyList<DevelopDefectBrushEdit> Brushes,
        IReadOnlyList<DevelopDefectRecipeEditRef> Order,
        DevelopRequestRefusal Refusal)
    {
        public static Projection Invalid() =>
            new([], [], [], [], DevelopRequestRefusal.InvalidDefectRecipe);

        public static Projection Unsupported() =>
            new([], [], [], [], DevelopRequestRefusal.UnsupportedDefectEditKind);
    }
}
