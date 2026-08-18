namespace Negaflow.Catalog;

/// <summary>
/// recipe 항목의 각 조각을 검사하며 복사합니다. 입력을 그대로 참조하지 않고 반드시
/// 복사하는 이유는, 호출부가 나중에 고친 배열이 이미 검증된 snapshot 을 바꾸지
/// 못하게 하려는 것입니다.
/// </summary>
internal static class DefectRecipeCopier
{
    internal static bool TryValidateLabel(DefectEditLabel label) =>
        Enum.IsDefined(label.Kind) && label.Value >= 0;

    internal static bool TryCopySummary(
        DefectEditSummary? summary,
        out DefectEditSummary copy)
    {
        copy = null!;
        if (summary is null || !Enum.IsDefined(summary.Kind))
        {
            return false;
        }
        if (summary.Kind != DefectEditSummaryKind.ClassBreakdown)
        {
            if (summary.ClassBreakdown is not null)
            {
                return false;
            }
            copy = new DefectEditSummary(summary.Kind);
            return true;
        }
        if (summary.ClassBreakdown is not { } breakdown ||
            breakdown.Counts is null ||
            !double.IsFinite(breakdown.MeanConfidence) ||
            breakdown.MeanConfidence is < 0 or > 1)
        {
            return false;
        }

        HashSet<DefectClassification> classes = [];
        List<DefectClassCount> counts = new(breakdown.Counts.Count);
        int lastValue = -1;
        foreach (DefectClassCount value in breakdown.Counts)
        {
            int currentValue = (int)value.Classification;
            if (!Enum.IsDefined(value.Classification) ||
                value.Count < 0 ||
                !classes.Add(value.Classification) ||
                currentValue <= lastValue)
            {
                return false;
            }
            counts.Add(value);
            lastValue = currentValue;
        }
        copy = new DefectEditSummary(
            DefectEditSummaryKind.ClassBreakdown,
            new DefectClassBreakdown(
                counts.ToArray(),
                breakdown.MeanConfidence == 0.0 ? 0.0 : breakdown.MeanConfidence));
        return true;
    }

    internal static bool TryCopySize(DefectSize? size, out DefectSize? copy)
    {
        copy = null;
        if (size is null)
        {
            return true;
        }
        if (!IsPositiveFinite(size.Value.Width) ||
            !IsPositiveFinite(size.Value.Height))
        {
            return false;
        }
        copy = new DefectSize(
            NormalizeZero(size.Value.Width),
            NormalizeZero(size.Value.Height));
        return true;
    }

    internal static bool TryCopyPreview(
        IReadOnlyList<DefectPreviewComponent>? preview,
        ref int totalPoints,
        out IReadOnlyList<DefectPreviewComponent> copy)
    {
        copy = [];
        if (preview is null || preview.Count > DefectRecipeValidator.MaximumPreviewComponentsPerItem)
        {
            return false;
        }
        List<DefectPreviewComponent> values = new(preview.Count);
        foreach (DefectPreviewComponent? component in preview)
        {
            if (component is null ||
                !Enum.IsDefined(component.Classification) ||
                !double.IsFinite(component.Confidence) ||
                component.Confidence is < 0 or > 1 ||
                !TryCopyPoints(
                    component.Points,
                    DefectRecipeValidator.MaximumPointsPerRecipe,
                    ref totalPoints,
                    out IReadOnlyList<DefectPoint> points))
            {
                return false;
            }
            values.Add(new DefectPreviewComponent(
                component.Classification,
                NormalizeZero(component.Confidence),
                points));
        }
        copy = values.ToArray();
        return true;
    }

    internal static bool TryCopyStrokes(
        IReadOnlyList<DefectStroke>? strokes,
        ref int totalStrokes,
        ref int totalPoints,
        out IReadOnlyList<DefectStroke>? copy)
    {
        copy = null;
        if (strokes is null)
        {
            return true;
        }
        if (!TryAdd(strokes.Count, ref totalStrokes, DefectRecipeValidator.MaximumStrokesPerRecipe) ||
            strokes.Count > DefectRecipeValidator.MaximumStrokesPerItem)
        {
            return false;
        }
        List<DefectStroke> values = new(strokes.Count);
        foreach (DefectStroke? stroke in strokes)
        {
            if (stroke is null ||
                !double.IsFinite(stroke.Thickness) ||
                stroke.Thickness < 0 ||
                !TryCopyPoints(
                    stroke.Points,
                    DefectRecipeValidator.MaximumPointsPerStroke,
                    ref totalPoints,
                    out IReadOnlyList<DefectPoint> points))
            {
                return false;
            }
            values.Add(new DefectStroke(points, NormalizeZero(stroke.Thickness)));
        }
        copy = values.ToArray();
        return true;
    }

    internal static bool TryCopyCloneStrokes(
        IReadOnlyList<DefectCloneStroke>? strokes,
        ref int totalStrokes,
        ref int totalPoints,
        out IReadOnlyList<DefectCloneStroke>? copy)
    {
        copy = null;
        if (strokes is null)
        {
            return true;
        }
        if (!TryAdd(strokes.Count, ref totalStrokes, DefectRecipeValidator.MaximumStrokesPerRecipe) ||
            strokes.Count > DefectRecipeValidator.MaximumStrokesPerItem)
        {
            return false;
        }
        List<DefectCloneStroke> values = new(strokes.Count);
        foreach (DefectCloneStroke? stroke in strokes)
        {
            if (stroke is null ||
                !TryCopyPoints(
                    stroke.Points,
                    DefectRecipeValidator.MaximumPointsPerStroke,
                    ref totalPoints,
                    out IReadOnlyList<DefectPoint> points) ||
                !double.IsFinite(stroke.OffsetX) ||
                !double.IsFinite(stroke.OffsetY) ||
                !IsPositiveFinite(stroke.Diameter) ||
                !double.IsFinite(stroke.Hardness) ||
                stroke.Hardness is < 0 or > 1)
            {
                return false;
            }
            values.Add(new DefectCloneStroke(
                points,
                NormalizeZero(stroke.OffsetX),
                NormalizeZero(stroke.OffsetY),
                stroke.Diameter,
                NormalizeZero(stroke.Hardness)));
        }
        copy = values.ToArray();
        return true;
    }

    internal static bool TryCopyClusters(
        IReadOnlyList<DefectCluster>? clusters,
        bool validateCompressedMasks,
        ref int totalClusters,
        ref long decodedByteCount,
        out IReadOnlyList<DefectCluster>? copy)
    {
        copy = null;
        if (clusters is null)
        {
            return true;
        }
        if (clusters.Count > DefectRecipeValidator.MaximumClustersPerItem ||
            !TryAdd(clusters.Count, ref totalClusters, DefectRecipeValidator.MaximumClustersPerRecipe))
        {
            return false;
        }
        List<DefectCluster> values = new(clusters.Count);
        foreach (DefectCluster? cluster in clusters)
        {
            if (cluster is null ||
                !TryCopyRect(cluster.Roi, out DefectRect roi) ||
                !TryCopyMask(
                    cluster.Mask,
                    cluster.Width,
                    cluster.Height,
                    validateCompressedMasks,
                    ref decodedByteCount,
                    out DefectMask mask) ||
                !TryCopyAttenuation(
                    cluster.AttenuationR16,
                    cluster.Width,
                    cluster.Height,
                    validateCompressedMasks,
                    ref decodedByteCount,
                    out DefectMask? attenuation))
            {
                return false;
            }
            values.Add(new DefectCluster(
                roi,
                mask,
                cluster.Width,
                cluster.Height,
                attenuation));
        }
        copy = values.ToArray();
        return true;
    }

    internal static bool TryCopyPoints(
        IReadOnlyList<DefectPoint>? points,
        int perCollectionLimit,
        ref int totalPoints,
        out IReadOnlyList<DefectPoint> copy)
    {
        copy = [];
        if (points is null || points.Count > perCollectionLimit ||
            !TryAdd(points.Count, ref totalPoints, DefectRecipeValidator.MaximumPointsPerRecipe))
        {
            return false;
        }
        DefectPoint[] values = new DefectPoint[points.Count];
        for (int index = 0; index < points.Count; ++index)
        {
            DefectPoint point = points[index];
            if (!double.IsFinite(point.X) || !double.IsFinite(point.Y))
            {
                return false;
            }
            values[index] = new DefectPoint(
                NormalizeZero(point.X),
                NormalizeZero(point.Y));
        }
        copy = values;
        return true;
    }

    internal static bool TryCopyRect(DefectRect rect, out DefectRect copy)
    {
        copy = default;
        if (!double.IsFinite(rect.X) || !double.IsFinite(rect.Y) ||
            !IsPositiveFinite(rect.Width) || !IsPositiveFinite(rect.Height))
        {
            return false;
        }
        copy = new DefectRect(
            NormalizeZero(rect.X),
            NormalizeZero(rect.Y),
            rect.Width,
            rect.Height);
        return true;
    }

    internal static bool TryCopyMask(
        DefectMask? mask,
        int width,
        int height,
        bool validateCompressedMask,
        ref long decodedByteCount,
        out DefectMask copy) =>
        TryCopyPixelPayload(
            mask,
            width,
            height,
            bytesPerPixel: 4,
            validateCompressedMask,
            ref decodedByteCount,
            out copy);

    internal static bool TryCopyAttenuation(
        DefectMask? attenuation,
        int width,
        int height,
        bool validateCompressedPayload,
        ref long decodedByteCount,
        out DefectMask? copy)
    {
        copy = null;
        if (attenuation is null)
        {
            return true;
        }
        if (!TryCopyPixelPayload(
                attenuation,
                width,
                height,
                bytesPerPixel: 2,
                validateCompressedPayload,
                ref decodedByteCount,
                out DefectMask value))
        {
            return false;
        }
        copy = value;
        return true;
    }

    internal static bool TryCopyPixelPayload(
        DefectMask? mask,
        int width,
        int height,
        int bytesPerPixel,
        bool validateCompressedMask,
        ref long decodedByteCount,
        out DefectMask copy)
    {
        copy = null!;
        if (mask?.Data is null || width <= 0 || height <= 0)
        {
            return false;
        }

        long pixels;
        long expectedBytes;
        try
        {
            pixels = checked((long)width * height);
            expectedBytes = checked(pixels * bytesPerPixel);
            decodedByteCount = checked(decodedByteCount + expectedBytes);
        }
        catch (OverflowException)
        {
            return false;
        }
        if (pixels > DefectRecipeValidator.MaximumMaskPixels ||
            decodedByteCount > DefectRecipeValidator.MaximumDecompressedBytesPerRecipe ||
            mask.IsZlib && mask.Data.Length == 0 ||
            !mask.IsZlib && mask.Data.LongLength != expectedBytes)
        {
            return false;
        }

        byte[] data = mask.Data.ToArray();
        if (mask.IsZlib && validateCompressedMask &&
            !DefectRecipeMaskCompression.HasExactZlibOutput(data, expectedBytes))
        {
            return false;
        }
        copy = new DefectMask(mask.IsZlib, data);
        return true;
    }

    internal static bool TryAdd(int value, ref int total, int maximum)
    {
        if (value < 0 || total > maximum - value)
        {
            return false;
        }
        total += value;
        return true;
    }

    internal static bool IsPositiveFinite(double value) =>
        double.IsFinite(value) && value > 0;

    internal static double NormalizeZero(double value) => value == 0.0 ? 0.0 : value;
}
