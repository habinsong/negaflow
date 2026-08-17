namespace Negaflow.Interop;

internal sealed record NativeDefectClonePayload(
    NativeDefectCloneEditV1[] Edits,
    NativeDefectCloneStrokeV1[] Strokes,
    NativeDefectClonePointV1[] Points);

internal sealed record NativeDefectBrushPayload(
    NativeDefectBrushEditV1[] Edits,
    NativeDefectBrushStrokeV1[] Strokes,
    NativeDefectBrushPointV1[] Points);

/// <summary>복제·브러시·편집 순서 페이로드입니다.</summary>
internal static class NativeDevelopDefectStrokePayload
{
    internal static NativeDefectClonePayload BuildDefectClonePayload(
        IReadOnlyList<DevelopDefectCloneEdit> source)
    {
        List<NativeDefectCloneEditV1> edits = new(source.Count);
        List<NativeDefectCloneStrokeV1> strokes = [];
        List<NativeDefectClonePointV1> points = [];
        foreach (DevelopDefectCloneEdit edit in source)
        {
            uint strokeOffset = checked((uint)strokes.Count);
            foreach (DevelopDefectCloneStroke stroke in edit.Strokes)
            {
                uint pointOffset = checked((uint)points.Count);
                foreach (DevelopDefectClonePoint point in stroke.Points)
                {
                    points.Add(new NativeDefectClonePointV1
                    {
                        X = point.X,
                        Y = point.Y,
                    });
                }
                strokes.Add(new NativeDefectCloneStrokeV1
                {
                    PointOffset = pointOffset,
                    PointCount = checked((uint)stroke.Points.Count),
                    OffsetX = stroke.OffsetX,
                    OffsetY = stroke.OffsetY,
                    DiameterPixels = stroke.DiameterPixels,
                    Hardness = stroke.Hardness,
                });
            }
            edits.Add(new NativeDefectCloneEditV1
            {
                Enabled = edit.IsEnabled ? 1U : 0U,
                StrokeOffset = strokeOffset,
                StrokeCount = checked((uint)edit.Strokes.Count),
                Strength = edit.Strength,
            });
        }
        return new NativeDefectClonePayload([.. edits], [.. strokes], [.. points]);
    }

    internal static NativeDefectBrushPayload BuildDefectBrushPayload(
        IReadOnlyList<DevelopDefectBrushEdit> source)
    {
        List<NativeDefectBrushEditV1> edits = new(source.Count);
        List<NativeDefectBrushStrokeV1> strokes = [];
        List<NativeDefectBrushPointV1> points = [];
        foreach (DevelopDefectBrushEdit edit in source)
        {
            uint strokeOffset = checked((uint)strokes.Count);
            foreach (DevelopDefectBrushStroke stroke in edit.Strokes)
            {
                uint pointOffset = checked((uint)points.Count);
                foreach (DevelopDefectBrushPoint point in stroke.Points)
                {
                    points.Add(new NativeDefectBrushPointV1
                    {
                        X = point.X,
                        Y = point.Y,
                    });
                }
                strokes.Add(new NativeDefectBrushStrokeV1
                {
                    PointOffset = pointOffset,
                    PointCount = checked((uint)stroke.Points.Count),
                    Thickness = stroke.Thickness,
                });
            }
            edits.Add(new NativeDefectBrushEditV1
            {
                Enabled = edit.IsEnabled ? 1U : 0U,
                StrokeOffset = strokeOffset,
                StrokeCount = checked((uint)edit.Strokes.Count),
                Strength = edit.Strength,
            });
        }
        return new NativeDefectBrushPayload([.. edits], [.. strokes], [.. points]);
    }

    internal static NativeDefectRecipeEditRefV1[] BuildDefectEditOrder(
        DevelopExportRequest request)
    {
        if (request.DefectEditOrder.Count == 0)
        {
            NativeDefectRecipeEditRefV1[] regions =
                new NativeDefectRecipeEditRefV1[request.DefectRegions.Count];
            for (int index = 0; index < regions.Length; ++index)
            {
                regions[index] = new NativeDefectRecipeEditRefV1
                {
                    Kind = (uint)DevelopDefectEditKind.Region,
                    Index = checked((uint)index),
                };
            }
            return regions;
        }
        int[] infraredClusterOffsets = new int[request.DefectInfrared.Count];
        int infraredClusterCount = 0;
        for (int index = 0; index < request.DefectInfrared.Count; ++index)
        {
            infraredClusterOffsets[index] = infraredClusterCount;
            infraredClusterCount = checked(
                infraredClusterCount + request.DefectInfrared[index].Clusters.Count);
        }
        List<NativeDefectRecipeEditRefV1> order = new(
            checked(request.DefectEditOrder.Count - request.DefectInfrared.Count +
                infraredClusterCount));
        foreach (DevelopDefectRecipeEditRef reference in request.DefectEditOrder)
        {
            if (reference.Kind != DevelopDefectEditKind.Infrared)
            {
                order.Add(new NativeDefectRecipeEditRefV1
                {
                    Kind = (uint)reference.Kind,
                    Index = reference.Index,
                });
                continue;
            }
            int itemIndex = checked((int)reference.Index);
            int firstCluster = infraredClusterOffsets[itemIndex];
            for (int ordinal = 0;
                 ordinal < request.DefectInfrared[itemIndex].Clusters.Count;
                 ++ordinal)
            {
                order.Add(new NativeDefectRecipeEditRefV1
                {
                    Kind = (uint)DevelopDefectEditKind.Region,
                    Index = checked((uint)(request.DefectRegions.Count +
                        firstCluster + ordinal)),
                });
            }
        }
        return [.. order];
    }
}
