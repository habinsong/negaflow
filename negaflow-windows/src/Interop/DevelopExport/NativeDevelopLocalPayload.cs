namespace Negaflow.Interop;

internal sealed record NativeLocalDodgeBurnPayload(
    NativeLocalDodgeBurnAdjustmentV1[] Adjustments,
    NativeLocalDodgeBurnStrokeV1[] Strokes,
    NativeLocalDodgeBurnPointV1[] Points);

/// <summary>로컬 닷지/번 네이티브 페이로드입니다.</summary>
internal static class NativeDevelopLocalPayload
{
    internal static NativeLocalDodgeBurnPayload BuildLocalDodgeBurnPayload(
        IReadOnlyList<DevelopLocalDodgeBurnAdjustment> source)
    {
        List<NativeLocalDodgeBurnAdjustmentV1> adjustments = new(source.Count);
        List<NativeLocalDodgeBurnStrokeV1> strokes = [];
        List<NativeLocalDodgeBurnPointV1> points = [];
        foreach (DevelopLocalDodgeBurnAdjustment adjustment in source)
        {
            uint strokeOffset = 0U;
            uint strokeCount = 0U;
            uint pointOffset = 0U;
            uint pointCount = 0U;
            if (adjustment.Mask.Kind == DevelopLocalDodgeBurnMaskKind.Brush)
            {
                strokeOffset = checked((uint)strokes.Count);
                strokeCount = checked((uint)adjustment.Mask.Strokes.Count);
                foreach (DevelopLocalDodgeBurnStroke stroke in adjustment.Mask.Strokes)
                {
                    uint strokePointOffset = checked((uint)points.Count);
                    foreach (DevelopLocalDodgeBurnPoint point in stroke.Points)
                    {
                        points.Add(new NativeLocalDodgeBurnPointV1
                        {
                            X = (float)point.X,
                            Y = (float)point.Y,
                        });
                    }
                    strokes.Add(new NativeLocalDodgeBurnStrokeV1
                    {
                        PointOffset = strokePointOffset,
                        PointCount = checked((uint)stroke.Points.Count),
                        Thickness = (float)stroke.Thickness,
                        Feather = (float)stroke.Feather,
                    });
                }
            }
            else if (adjustment.Mask.Kind == DevelopLocalDodgeBurnMaskKind.Polygon)
            {
                pointOffset = checked((uint)points.Count);
                pointCount = checked((uint)adjustment.Mask.Points.Count);
                foreach (DevelopLocalDodgeBurnPoint point in adjustment.Mask.Points)
                {
                    points.Add(new NativeLocalDodgeBurnPointV1
                    {
                        X = (float)point.X,
                        Y = (float)point.Y,
                    });
                }
            }
            adjustments.Add(new NativeLocalDodgeBurnAdjustmentV1
            {
                Mode = (uint)adjustment.Mode,
                Enabled = adjustment.IsEnabled ? 1U : 0U,
                MaskKind = (uint)adjustment.Mask.Kind,
                StrokeOffset = strokeOffset,
                StrokeCount = strokeCount,
                PointOffset = pointOffset,
                PointCount = pointCount,
                Amount = (float)adjustment.Amount,
                CenterX = (float)adjustment.Mask.Center.X,
                CenterY = (float)adjustment.Mask.Center.Y,
                Radius = (float)adjustment.Mask.Radius,
                Feather = (float)adjustment.Mask.Feather,
                StartX = (float)adjustment.Mask.Start.X,
                StartY = (float)adjustment.Mask.Start.Y,
                EndX = (float)adjustment.Mask.End.X,
                EndY = (float)adjustment.Mask.End.Y,
            });
        }
        return new NativeLocalDodgeBurnPayload(
            [.. adjustments],
            [.. strokes],
            [.. points]);
    }
}
