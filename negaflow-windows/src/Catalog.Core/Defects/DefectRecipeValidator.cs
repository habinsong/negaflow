using System.IO.Compression;

namespace Negaflow.Catalog;

internal static class DefectRecipeValidator
{
    public const int MaximumItems = 4_096;
    public const int MaximumStrokesPerItem = 50_000;
    public const int MaximumStrokesPerRecipe = 100_000;
    public const int MaximumPointsPerStroke = 1_000_000;
    public const int MaximumPointsPerRecipe = 5_000_000;
    public const int MaximumPreviewComponentsPerItem = 100_000;
    public const int MaximumPreviewPointsPerRecipe = 5_000_000;
    public const int MaximumClustersPerItem = 100_000;
    public const int MaximumClustersPerRecipe = 100_000;
    public const long MaximumMaskPixels = 100_000_000;
    public const long MaximumDecompressedBytesPerRecipe = 512L * 1_024 * 1_024;

    public static DefectRecipeSnapshot CreateSnapshot(
        Guid frameId,
        ulong recipeRevision,
        DefectSourceIdentity? sourceIdentity,
        IReadOnlyList<DefectEditItem> items)
    {
        ArgumentNullException.ThrowIfNull(items);
        IReadOnlyList<DefectEditItem> storageItems;
        try
        {
            storageItems = CompressRawMasks(items);
        }
        catch (Exception error) when (error is IOException or InvalidDataException)
        {
            throw new ArgumentException("Invalid Defects mask.", nameof(items), error);
        }
        if (!TryNormalizeItems(
                storageItems,
                validateCompressedMasks: false,
                out var normalized) ||
            frameId == Guid.Empty ||
            recipeRevision == 0 ||
            !IsValidSourceIdentity(sourceIdentity))
        {
            throw new ArgumentException("Invalid Defects recipe snapshot.");
        }

        return new DefectRecipeSnapshot(
            frameId,
            DefectRecipeFingerprint.CurrentVersion,
            recipeRevision,
            DefectRecipeFingerprint.Compute(normalized),
            sourceIdentity,
            normalized);
    }

    public static bool TryCreateDecodedSnapshot(
        Guid expectedFrameId,
        Guid frameId,
        int fingerprintVersion,
        ulong recipeRevision,
        string recipeSha256,
        DefectSourceIdentity? sourceIdentity,
        IReadOnlyList<DefectEditItem> items,
        bool validateCompressedMasks,
        out DefectRecipeSnapshot snapshot)
    {
        snapshot = null!;
        if (expectedFrameId == Guid.Empty ||
            frameId != expectedFrameId ||
            fingerprintVersion is not DefectRecipeFingerprint.LegacyVersion and
                not DefectRecipeFingerprint.CurrentVersion ||
            recipeRevision == 0 ||
            !IsLowercaseSha256(recipeSha256) ||
            !IsValidSourceIdentity(sourceIdentity) ||
            !TryNormalizeItems(items, validateCompressedMasks, out var normalized))
        {
            return false;
        }

        string computed = DefectRecipeFingerprint.Compute(
            normalized,
            fingerprintVersion);
        if (!string.Equals(computed, recipeSha256, StringComparison.Ordinal))
        {
            return false;
        }

        snapshot = fingerprintVersion == DefectRecipeFingerprint.CurrentVersion
            ? new DefectRecipeSnapshot(
                frameId,
                fingerprintVersion,
                recipeRevision,
                recipeSha256,
                sourceIdentity,
                normalized)
            : new DefectRecipeSnapshot(
                frameId,
                DefectRecipeFingerprint.CurrentVersion,
                recipeRevision,
                DefectRecipeFingerprint.Compute(normalized),
                sourceIdentity,
                normalized);
        return true;
    }

    public static bool IsValidSourceIdentity(DefectSourceIdentity? identity) =>
        identity is null ||
        identity.Value.ByteCount > 0 && IsLowercaseSha256(identity.Value.Sha256);

    public static bool IsLowercaseSha256(string? value) =>
        value is { Length: 64 } && value.All(character =>
            character is >= '0' and <= '9' or >= 'a' and <= 'f');

    private static bool TryNormalizeItems(
        IReadOnlyList<DefectEditItem> items,
        bool validateCompressedMasks,
        out IReadOnlyList<DefectEditItem> normalized)
    {
        normalized = [];
        if (items.Count > MaximumItems)
        {
            return false;
        }

        int strokeCount = 0;
        int strokePointCount = 0;
        int previewPointCount = 0;
        int clusterCount = 0;
        long decodedByteCount = 0;
        HashSet<Guid> itemIds = [];
        List<DefectEditItem> copies = new(items.Count);

        foreach (DefectEditItem? item in items)
        {
            if (item is null ||
                item.Id == Guid.Empty ||
                !itemIds.Add(item.Id) ||
                !Enum.IsDefined(item.Kind) ||
                !double.IsFinite(item.Strength) ||
                item.Strength is < 0 or > 1 ||
                !TryValidateLabel(item.Label) ||
                !TryCopySummary(item.Summary, out DefectEditSummary summary) ||
                !TryCopySize(item.BaseSize, out DefectSize? baseSize) ||
                !TryCopyPreview(
                    item.Preview,
                    ref previewPointCount,
                    out IReadOnlyList<DefectPreviewComponent> preview))
            {
                return false;
            }

            DefectEditItem copy = new(
                item.Id,
                item.Kind,
                item.Enabled,
                item.Strength == 0.0 ? 0.0 : item.Strength,
                item.Label,
                summary,
                baseSize,
                preview);

            switch (item.Kind)
            {
                case DefectEditKind.Brush:
                    if (item.RegionMask is not null || item.RegionRoi is not null ||
                        item.RegionWidth is not null || item.RegionHeight is not null ||
                        item.Clusters is not null || item.CloneStrokes is not null ||
                        !TryCopyStrokes(
                            item.Strokes,
                            ref strokeCount,
                            ref strokePointCount,
                            out IReadOnlyList<DefectStroke>? strokes))
                    {
                        return false;
                    }
                    copy = copy with { Strokes = strokes };
                    break;
                case DefectEditKind.Region:
                    if (item.Strokes is not null || item.Clusters is not null ||
                        item.CloneStrokes is not null || item.RegionMask is null ||
                        item.RegionRoi is not { } regionRoi ||
                        item.RegionWidth is not { } regionWidth ||
                        item.RegionHeight is not { } regionHeight ||
                        !TryCopyRect(regionRoi, out DefectRect copiedRoi) ||
                        !TryCopyMask(
                            item.RegionMask,
                            regionWidth,
                            regionHeight,
                            validateCompressedMasks,
                            ref decodedByteCount,
                            out DefectMask regionMask))
                    {
                        return false;
                    }
                    copy = copy with
                    {
                        RegionMask = regionMask,
                        RegionRoi = copiedRoi,
                        RegionWidth = regionWidth,
                        RegionHeight = regionHeight,
                    };
                    break;
                case DefectEditKind.Infrared:
                    if (item.Strokes is not null || item.RegionMask is not null ||
                        item.RegionRoi is not null || item.RegionWidth is not null ||
                        item.RegionHeight is not null || item.CloneStrokes is not null ||
                        !TryCopyClusters(
                            item.Clusters,
                            validateCompressedMasks,
                            ref clusterCount,
                            ref decodedByteCount,
                            out IReadOnlyList<DefectCluster>? clusters))
                    {
                        return false;
                    }
                    copy = copy with { Clusters = clusters };
                    break;
                case DefectEditKind.Clone:
                    if (item.Strokes is not null || item.RegionMask is not null ||
                        item.RegionRoi is not null || item.RegionWidth is not null ||
                        item.RegionHeight is not null || item.Clusters is not null ||
                        !TryCopyCloneStrokes(
                            item.CloneStrokes,
                            ref strokeCount,
                            ref strokePointCount,
                            out IReadOnlyList<DefectCloneStroke>? cloneStrokes))
                    {
                        return false;
                    }
                    copy = copy with { CloneStrokes = cloneStrokes };
                    break;
                default:
                    return false;
            }
            copies.Add(copy);
        }

        normalized = copies.ToArray();
        return true;
    }

    private static IReadOnlyList<DefectEditItem> CompressRawMasks(
        IReadOnlyList<DefectEditItem> items)
    {
        DefectEditItem[] copies = new DefectEditItem[items.Count];
        for (int index = 0; index < items.Count; ++index)
        {
            DefectEditItem? item = items[index];
            if (item is null || item.Clusters?.Any(cluster => cluster is null) == true)
            {
                return items;
            }
            DefectMask? regionMask = item.RegionMask is { } mask
                ? Compress(mask)
                : null;
            IReadOnlyList<DefectCluster>? clusters = item.Clusters?.Select(cluster =>
                cluster with
                {
                    Mask = Compress(cluster.Mask),
                    AttenuationR16 = cluster.AttenuationR16 is { } attenuation
                        ? Compress(attenuation)
                        : null,
                }).ToArray();
            copies[index] = item with
            {
                RegionMask = regionMask,
                Clusters = clusters,
            };
        }
        return copies;
    }

    private static DefectMask Compress(DefectMask mask)
    {
        if (mask.Data is null || mask.IsZlib || mask.Data.Length == 0)
        {
            return mask;
        }
        using MemoryStream output = new();
        using (ZLibStream zlib = new(
            output,
            CompressionLevel.SmallestSize,
            leaveOpen: true))
        {
            zlib.Write(mask.Data);
        }
        return new DefectMask(true, output.ToArray());
    }

    private static bool TryValidateLabel(DefectEditLabel label) =>
        Enum.IsDefined(label.Kind) && label.Value >= 0;

    private static bool TryCopySummary(
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

    private static bool TryCopySize(DefectSize? size, out DefectSize? copy)
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

    private static bool TryCopyPreview(
        IReadOnlyList<DefectPreviewComponent>? preview,
        ref int totalPoints,
        out IReadOnlyList<DefectPreviewComponent> copy)
    {
        copy = [];
        if (preview is null || preview.Count > MaximumPreviewComponentsPerItem)
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
                    MaximumPointsPerRecipe,
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

    private static bool TryCopyStrokes(
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
        if (!TryAdd(strokes.Count, ref totalStrokes, MaximumStrokesPerRecipe) ||
            strokes.Count > MaximumStrokesPerItem)
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
                    MaximumPointsPerStroke,
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

    private static bool TryCopyCloneStrokes(
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
        if (!TryAdd(strokes.Count, ref totalStrokes, MaximumStrokesPerRecipe) ||
            strokes.Count > MaximumStrokesPerItem)
        {
            return false;
        }
        List<DefectCloneStroke> values = new(strokes.Count);
        foreach (DefectCloneStroke? stroke in strokes)
        {
            if (stroke is null ||
                !TryCopyPoints(
                    stroke.Points,
                    MaximumPointsPerStroke,
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

    private static bool TryCopyClusters(
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
        if (clusters.Count > MaximumClustersPerItem ||
            !TryAdd(clusters.Count, ref totalClusters, MaximumClustersPerRecipe))
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

    private static bool TryCopyPoints(
        IReadOnlyList<DefectPoint>? points,
        int perCollectionLimit,
        ref int totalPoints,
        out IReadOnlyList<DefectPoint> copy)
    {
        copy = [];
        if (points is null || points.Count > perCollectionLimit ||
            !TryAdd(points.Count, ref totalPoints, MaximumPointsPerRecipe))
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

    private static bool TryCopyRect(DefectRect rect, out DefectRect copy)
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

    private static bool TryCopyMask(
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

    private static bool TryCopyAttenuation(
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

    private static bool TryCopyPixelPayload(
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
        if (pixels > MaximumMaskPixels ||
            decodedByteCount > MaximumDecompressedBytesPerRecipe ||
            mask.IsZlib && mask.Data.Length == 0 ||
            !mask.IsZlib && mask.Data.LongLength != expectedBytes)
        {
            return false;
        }

        byte[] data = mask.Data.ToArray();
        if (mask.IsZlib && validateCompressedMask &&
            !HasExactZlibOutput(data, expectedBytes))
        {
            return false;
        }
        copy = new DefectMask(mask.IsZlib, data);
        return true;
    }

    private static bool HasExactZlibOutput(byte[] data, long expectedBytes)
    {
        try
        {
            using MemoryStream source = new(data, writable: false);
            using ZLibStream zlib = new(source, CompressionMode.Decompress, leaveOpen: false);
            byte[] buffer = new byte[64 * 1_024];
            long total = 0;
            while (true)
            {
                int read = zlib.Read(buffer);
                if (read == 0)
                {
                    break;
                }
                total += read;
                if (total > expectedBytes)
                {
                    return false;
                }
            }
            return total == expectedBytes && source.Position == source.Length;
        }
        catch (Exception error) when (error is InvalidDataException or IOException)
        {
            return false;
        }
    }

    private static bool TryAdd(int value, ref int total, int maximum)
    {
        if (value < 0 || total > maximum - value)
        {
            return false;
        }
        total += value;
        return true;
    }

    private static bool IsPositiveFinite(double value) =>
        double.IsFinite(value) && value > 0;

    private static double NormalizeZero(double value) => value == 0.0 ? 0.0 : value;
}
