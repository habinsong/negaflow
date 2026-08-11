using System.Runtime.CompilerServices;
using Negaflow.Catalog;
using Negaflow.Interop;

namespace Negaflow.Shell;

internal static class DefectRecipeProjector
{
    private const int MaximumNativeRegionEdits = 4_096;
    private const int MaximumNativeOrderedEdits = 8_192;
    private static readonly ConditionalWeakTable<
        DefectRecipeSnapshot,
        Projection> Cache = new();

    public static bool TryProject(
        DefectRecipeSnapshot? recipe,
        out IReadOnlyList<DevelopDefectRegionEdit> regions,
        out IReadOnlyList<DevelopDefectInfraredEdit> infrared,
        out IReadOnlyList<DevelopDefectCloneEdit> clones,
        out IReadOnlyList<DevelopDefectBrushEdit> brushes,
        out IReadOnlyList<DevelopDefectRecipeEditRef> order,
        out DevelopRequestRefusal refusal)
    {
        if (recipe is null)
        {
            regions = [];
            infrared = [];
            clones = [];
            brushes = [];
            order = [];
            refusal = DevelopRequestRefusal.None;
            return true;
        }

        Projection projection = Cache.GetValue(recipe, Project);
        regions = projection.Regions;
        infrared = projection.Infrared;
        clones = projection.Clones;
        brushes = projection.Brushes;
        order = projection.Order;
        refusal = projection.Refusal;
        return refusal == DevelopRequestRefusal.None;
    }

    private static Projection Project(DefectRecipeSnapshot recipe)
    {
        List<DevelopDefectRegionEdit> regions = [];
        List<DevelopDefectInfraredEdit> infrared = [];
        List<DevelopDefectCloneEdit> clones = [];
        List<DevelopDefectBrushEdit> brushes = [];
        List<DevelopDefectRecipeEditRef> order = [];
        int nativeRegionDescriptorCount = 0;
        int nativeOrderReferenceCount = 0;
        foreach (DefectEditItem item in recipe.Items)
        {
            if (!item.Enabled)
            {
                continue;
            }
            switch (item.Kind)
            {
                case DefectEditKind.Region:
                    if (nativeRegionDescriptorCount >= MaximumNativeRegionEdits ||
                        nativeOrderReferenceCount >= MaximumNativeOrderedEdits ||
                        item.RegionMask is not { } mask ||
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
                    ++nativeRegionDescriptorCount;
                    ++nativeOrderReferenceCount;
                    break;
                case DefectEditKind.Infrared:
                    if (infrared.Count >= MaximumNativeRegionEdits ||
                        item.Clusters is not { Count: > 0 } sourceClusters ||
                        sourceClusters.Count >
                            MaximumNativeRegionEdits - nativeRegionDescriptorCount ||
                        sourceClusters.Count >
                            MaximumNativeOrderedEdits - nativeOrderReferenceCount)
                    {
                        return Projection.Invalid();
                    }
                    List<DevelopDefectInfraredCluster> projectedClusters = [];
                    foreach (DefectCluster cluster in sourceClusters)
                    {
                        if (!TryProjectInfraredCluster(
                                cluster, out DevelopDefectInfraredCluster projected))
                        {
                            return Projection.Invalid();
                        }
                        projectedClusters.Add(projected);
                    }
                    if (projectedClusters.Count == 0)
                    {
                        return Projection.Invalid();
                    }
                    infrared.Add(new DevelopDefectInfraredEdit
                    {
                        IsEnabled = item.Enabled,
                        Strength = item.Strength,
                        Clusters = projectedClusters.ToArray(),
                    });
                    order.Add(new(
                        DevelopDefectEditKind.Infrared,
                        checked((uint)infrared.Count - 1U)));
                    nativeRegionDescriptorCount += sourceClusters.Count;
                    nativeOrderReferenceCount += sourceClusters.Count;
                    break;
                case DefectEditKind.Brush:
                    if (nativeOrderReferenceCount >= MaximumNativeOrderedEdits ||
                        !TryAppendBrush(brushes, item.Strokes, item.Strength))
                    {
                        return Projection.Invalid();
                    }
                    order.Add(new(
                        DevelopDefectEditKind.Brush,
                        checked((uint)brushes.Count - 1U)));
                    ++nativeOrderReferenceCount;
                    break;
                case DefectEditKind.Clone:
                    if (nativeOrderReferenceCount >= MaximumNativeOrderedEdits ||
                        !TryAppendClone(clones, item.CloneStrokes, item.Strength))
                    {
                        return Projection.Invalid();
                    }
                    order.Add(new(
                        DevelopDefectEditKind.Clone,
                        checked((uint)clones.Count - 1U)));
                    ++nativeOrderReferenceCount;
                    break;
                default:
                    return Projection.Invalid();
            }
        }
        return new Projection(
            regions.ToArray(),
            infrared.ToArray(),
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

    private static bool TryProjectInfraredCluster(
        DefectCluster cluster,
        out DevelopDefectInfraredCluster projected)
    {
        projected = null!;
        DefectRect roi = cluster.Roi;
        int width = cluster.Width;
        int height = cluster.Height;
        if (width <= 0 || height <= 0 ||
            roi.X < 0 || roi.Y < 0 ||
            roi.Width != width || roi.Height != height ||
            roi.X != Math.Truncate(roi.X) || roi.Y != Math.Truncate(roi.Y) ||
            roi.X > uint.MaxValue || roi.Y > uint.MaxValue ||
            width > uint.MaxValue / 2 ||
            !DefectMaskCodec.TryDecodeRgba8(
                cluster.Mask,
                width,
                height,
                out byte[] rgbaMask))
        {
            return false;
        }

        byte[] coreMask = new byte[checked(width * height)];
        for (int pixel = 0; pixel < coreMask.Length; ++pixel)
        {
            coreMask[pixel] = rgbaMask[pixel * 4];
        }

        byte[]? attenuation = null;
        if (cluster.AttenuationR16 is { } payload &&
            !DefectMaskCodec.TryDecodeR16LittleEndian(
                payload,
                width,
                height,
                out attenuation))
        {
            return false;
        }
        projected = new DevelopDefectInfraredCluster
        {
            RoiX = (uint)roi.X,
            RoiY = (uint)roi.Y,
            Width = (uint)width,
            Height = (uint)height,
            CoreMaskStrideBytes = (uint)width,
            CoreMask = coreMask,
            AttenuationStrideBytes = attenuation is null ? 0U : (uint)width * 2,
            AttenuationR16 = attenuation is null
                ? (ReadOnlyMemory<byte>?)null
                : new ReadOnlyMemory<byte>(attenuation),
        };
        return true;
    }

    private sealed record Projection(
        IReadOnlyList<DevelopDefectRegionEdit> Regions,
        IReadOnlyList<DevelopDefectInfraredEdit> Infrared,
        IReadOnlyList<DevelopDefectCloneEdit> Clones,
        IReadOnlyList<DevelopDefectBrushEdit> Brushes,
        IReadOnlyList<DevelopDefectRecipeEditRef> Order,
        DevelopRequestRefusal Refusal)
    {
        public static Projection Invalid() =>
            new([], [], [], [], [], DevelopRequestRefusal.InvalidDefectRecipe);

        public static Projection Unsupported() =>
            new([], [], [], [], [], DevelopRequestRefusal.UnsupportedDefectEditKind);
    }
}
