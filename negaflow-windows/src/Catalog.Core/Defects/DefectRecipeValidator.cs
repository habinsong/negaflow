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
            storageItems = DefectRecipeMaskCompression.CompressRawMasks(items);
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
                !DefectRecipeCopier.TryValidateLabel(item.Label) ||
                !DefectRecipeCopier.TryCopySummary(item.Summary, out DefectEditSummary summary) ||
                !DefectRecipeCopier.TryCopySize(item.BaseSize, out DefectSize? baseSize) ||
                !DefectRecipeCopier.TryCopyPreview(
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
                        !DefectRecipeCopier.TryCopyStrokes(
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
                        !DefectRecipeCopier.TryCopyRect(regionRoi, out DefectRect copiedRoi) ||
                        !DefectRecipeCopier.TryCopyMask(
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
                        !DefectRecipeCopier.TryCopyClusters(
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
                        !DefectRecipeCopier.TryCopyCloneStrokes(
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
}
