namespace Negaflow.Interop;

using static NativeDevelopExportLimits;

/// <summary>결함 레시피 검증입니다. 페이로드 조립과 다른 이유입니다.</summary>
internal static class NativeDevelopDefectValidator
{
    internal static void ValidateDefectRegions(
        IReadOnlyList<DevelopDefectRegionEdit> edits)
    {
        ArgumentNullException.ThrowIfNull(edits);
        if (edits.Count > MaximumDefectRegionEdits)
        {
            throw new ArgumentException(
                "The defect recipe contains too many region edits.",
                nameof(edits));
        }
        long totalBytes = 0;
        foreach (DevelopDefectRegionEdit edit in edits)
        {
            ArgumentNullException.ThrowIfNull(edit);
            uint stride = edit.MaskStrideBytes == 0U
                ? edit.Width
                : edit.MaskStrideBytes;
            ulong required = edit.Height == 0U
                ? 0U
                : ((ulong)edit.Height - 1U) * stride + edit.Width;
            if (edit.Width <= 2U || edit.Height <= 2U ||
                stride < edit.Width || required > (ulong)edit.Mask.Length ||
                !double.IsFinite(edit.Strength) ||
                edit.Strength is < 0.0 or > 1.0 ||
                edit.PreferredAngleDegrees is { } angle &&
                    (!double.IsFinite(angle) || angle is < 0.0 or > 180.0))
            {
                throw new ArgumentException(
                    "A defect region edit has an invalid mask, strength, or angle.",
                    nameof(edits));
            }
            totalBytes = checked(totalBytes + edit.Mask.Length);
            if (totalBytes > MaximumDefectMaskBytes)
            {
                throw new ArgumentException(
                    "The defect recipe exceeds the bounded mask capacity.",
                    nameof(edits));
            }
        }
    }

    internal static void ValidateDefectInfrared(
        IReadOnlyList<DevelopDefectInfraredEdit> edits)
    {
        ArgumentNullException.ThrowIfNull(edits);
        if (edits.Count > MaximumDefectInfraredItems)
        {
            throw new ArgumentException(
                "The defect recipe contains too many infrared edits.",
                nameof(edits));
        }
        int totalClusters = 0;
        long totalAttenuationBytes = 0;
        foreach (DevelopDefectInfraredEdit edit in edits)
        {
            ArgumentNullException.ThrowIfNull(edit);
            ArgumentNullException.ThrowIfNull(edit.Clusters);
            if (edit.Clusters.Count == 0 ||
                !double.IsFinite(edit.Strength) || edit.Strength is < 0.0 or > 1.0)
            {
                throw new ArgumentException(
                    "An infrared edit has no clusters or an invalid strength.",
                    nameof(edits));
            }
            totalClusters = checked(totalClusters + edit.Clusters.Count);
            if (totalClusters > MaximumDefectInfraredClusters)
            {
                throw new ArgumentException(
                    "The defect recipe contains too many infrared clusters.",
                    nameof(edits));
            }
            foreach (DevelopDefectInfraredCluster cluster in edit.Clusters)
            {
                ArgumentNullException.ThrowIfNull(cluster);
                uint coreStride = cluster.CoreMaskStrideBytes == 0U
                    ? cluster.Width
                    : cluster.CoreMaskStrideBytes;
                ulong requiredCore = cluster.Height == 0U
                    ? 0U
                    : ((ulong)cluster.Height - 1U) * coreStride + cluster.Width;
                if (cluster.Width == 0U || cluster.Height == 0U ||
                    coreStride < cluster.Width ||
                    requiredCore != (ulong)cluster.CoreMask.Length)
                {
                    throw new ArgumentException(
                        "An infrared cluster has an invalid core mask.",
                        nameof(edits));
                }

                if (cluster.AttenuationR16 is not { } attenuation)
                {
                    if (cluster.AttenuationStrideBytes != 0U)
                    {
                        throw new ArgumentException(
                            "An infrared cluster without attenuation has a non-zero stride.",
                            nameof(edits));
                    }
                    continue;
                }

                ulong rowBytes = (ulong)cluster.Width * sizeof(ushort);
                uint attenuationStride = cluster.AttenuationStrideBytes == 0U
                    ? checked((uint)rowBytes)
                    : cluster.AttenuationStrideBytes;
                ulong requiredAttenuation = ((ulong)cluster.Height - 1U) *
                    attenuationStride + rowBytes;
                if (attenuationStride < rowBytes ||
                    requiredAttenuation != (ulong)attenuation.Length)
                {
                    throw new ArgumentException(
                        "An infrared cluster has an invalid attenuation layout.",
                        nameof(edits));
                }
                totalAttenuationBytes = checked(
                    totalAttenuationBytes + attenuation.Length);
                if (totalAttenuationBytes > MaximumDefectInfraredAttenuationBytes)
                {
                    throw new ArgumentException(
                        "The infrared recipe exceeds the bounded attenuation capacity.",
                        nameof(edits));
                }
            }
        }
    }

    internal static void ValidateCombinedDefectRegionPayload(
        IReadOnlyList<DevelopDefectRegionEdit> regions,
        IReadOnlyList<DevelopDefectInfraredEdit> infrared)
    {
        int infraredClusterCount = 0;
        foreach (DevelopDefectInfraredEdit item in infrared)
        {
            infraredClusterCount = checked(infraredClusterCount + item.Clusters.Count);
        }
        if (regions.Count >
            MaximumDefectNativeRegionDescriptors - infraredClusterCount)
        {
            throw new ArgumentException(
                "The combined region and infrared recipe exceeds native capacity.");
        }
        long totalMaskBytes = 0;
        foreach (DevelopDefectRegionEdit edit in regions)
        {
            totalMaskBytes += edit.Mask.Length;
        }
        foreach (DevelopDefectInfraredEdit item in infrared)
        {
            foreach (DevelopDefectInfraredCluster cluster in item.Clusters)
            {
                totalMaskBytes += cluster.CoreMask.Length;
            }
        }
        if (totalMaskBytes > MaximumDefectMaskBytes)
        {
            throw new ArgumentException(
                "The combined region and infrared masks exceed native capacity.");
        }
    }

    internal static void ValidateDefectClones(
        IReadOnlyList<DevelopDefectCloneEdit> edits)
    {
        ArgumentNullException.ThrowIfNull(edits);
        if (edits.Count > MaximumDefectCloneEdits)
        {
            throw new ArgumentException(
                "The defect recipe contains too many clone edits.",
                nameof(edits));
        }
        long totalStrokes = 0;
        long totalPoints = 0;
        foreach (DevelopDefectCloneEdit edit in edits)
        {
            ArgumentNullException.ThrowIfNull(edit);
            ArgumentNullException.ThrowIfNull(edit.Strokes);
            if (!double.IsFinite(edit.Strength) || edit.Strength is < 0.0 or > 1.0)
            {
                throw new ArgumentException(
                    "A clone edit has an invalid strength.", nameof(edits));
            }
            totalStrokes = checked(totalStrokes + edit.Strokes.Count);
            foreach (DevelopDefectCloneStroke stroke in edit.Strokes)
            {
                ArgumentNullException.ThrowIfNull(stroke);
                ArgumentNullException.ThrowIfNull(stroke.Points);
                if (!double.IsFinite(stroke.OffsetX) ||
                    !double.IsFinite(stroke.OffsetY) ||
                    !double.IsFinite(stroke.DiameterPixels) ||
                    stroke.DiameterPixels <= 0.0 ||
                    !double.IsFinite(stroke.Hardness) ||
                    stroke.Hardness is < 0.0 or > 1.0)
                {
                    throw new ArgumentException(
                        "A clone stroke has invalid geometry.", nameof(edits));
                }
                totalPoints = checked(totalPoints + stroke.Points.Count);
                foreach (DevelopDefectClonePoint point in stroke.Points)
                {
                    if (!double.IsFinite(point.X) || !double.IsFinite(point.Y))
                    {
                        throw new ArgumentException(
                            "A clone stroke contains a non-finite point.", nameof(edits));
                    }
                }
            }
            if (totalStrokes > MaximumDefectCloneStrokes ||
                totalPoints > MaximumDefectClonePoints)
            {
                throw new ArgumentException(
                    "The clone recipe exceeds the bounded stroke or point capacity.",
                    nameof(edits));
            }
        }
    }

    internal static void ValidateDefectBrushes(
        IReadOnlyList<DevelopDefectBrushEdit> edits)
    {
        ArgumentNullException.ThrowIfNull(edits);
        if (edits.Count > MaximumDefectBrushEdits)
        {
            throw new ArgumentException(
                "The defect recipe contains too many brush edits.",
                nameof(edits));
        }
        long totalStrokes = 0;
        long totalPoints = 0;
        foreach (DevelopDefectBrushEdit edit in edits)
        {
            ArgumentNullException.ThrowIfNull(edit);
            ArgumentNullException.ThrowIfNull(edit.Strokes);
            if (!double.IsFinite(edit.Strength) || edit.Strength is < 0.0 or > 1.0)
            {
                throw new ArgumentException(
                    "A brush edit has an invalid strength.", nameof(edits));
            }
            totalStrokes = checked(totalStrokes + edit.Strokes.Count);
            foreach (DevelopDefectBrushStroke stroke in edit.Strokes)
            {
                ArgumentNullException.ThrowIfNull(stroke);
                ArgumentNullException.ThrowIfNull(stroke.Points);
                if (!double.IsFinite(stroke.Thickness) ||
                    stroke.Thickness is < 0.0 or > 1.0)
                {
                    throw new ArgumentException(
                        "A brush stroke has invalid geometry.", nameof(edits));
                }
                totalPoints = checked(totalPoints + stroke.Points.Count);
                foreach (DevelopDefectBrushPoint point in stroke.Points)
                {
                    if (!double.IsFinite(point.X) || !double.IsFinite(point.Y) ||
                        point.X is < 0.0 or > 1.0 ||
                        point.Y is < 0.0 or > 1.0)
                    {
                        throw new ArgumentException(
                            "A brush stroke contains a non-finite point.",
                            nameof(edits));
                    }
                }
            }
            if (totalStrokes > MaximumDefectBrushStrokes ||
                totalPoints > MaximumDefectBrushPoints)
            {
                throw new ArgumentException(
                    "The brush recipe exceeds the bounded stroke or point capacity.",
                    nameof(edits));
            }
        }
    }

    internal static void ValidateDefectEditOrder(DevelopExportRequest request)
    {
        ArgumentNullException.ThrowIfNull(request.DefectEditOrder);
        int infraredClusterCount = 0;
        foreach (DevelopDefectInfraredEdit item in request.DefectInfrared)
        {
            infraredClusterCount = checked(
                infraredClusterCount + item.Clusters.Count);
        }
        int expectedCount = checked(
            request.DefectRegions.Count + request.DefectInfrared.Count +
            request.DefectClones.Count + request.DefectBrushes.Count);
        int nativeExpectedCount = checked(
            request.DefectRegions.Count + infraredClusterCount +
            request.DefectClones.Count + request.DefectBrushes.Count);
        if (request.DefectEditOrder.Count == 0 && request.DefectClones.Count == 0 &&
            request.DefectBrushes.Count == 0 && request.DefectInfrared.Count == 0)
        {
            return;
        }
        if (expectedCount > MaximumDefectOrderedEdits ||
            nativeExpectedCount > MaximumDefectNativeOrderedEdits ||
            request.DefectEditOrder.Count != expectedCount)
        {
            throw new ArgumentException(
                "The defect edit order does not cover the complete recipe.",
                nameof(request));
        }
        bool[] regions = new bool[request.DefectRegions.Count];
        bool[] infrared = new bool[request.DefectInfrared.Count];
        bool[] clones = new bool[request.DefectClones.Count];
        bool[] brushes = new bool[request.DefectBrushes.Count];
        foreach (DevelopDefectRecipeEditRef reference in request.DefectEditOrder)
        {
            bool valid = reference.Kind switch
            {
                DevelopDefectEditKind.Region when reference.Index < regions.Length &&
                    !regions[reference.Index] => regions[reference.Index] = true,
                DevelopDefectEditKind.Clone when reference.Index < clones.Length &&
                    !clones[reference.Index] => clones[reference.Index] = true,
                DevelopDefectEditKind.Brush when reference.Index < brushes.Length &&
                    !brushes[reference.Index] => brushes[reference.Index] = true,
                DevelopDefectEditKind.Infrared when reference.Index < infrared.Length &&
                    !infrared[reference.Index] => infrared[reference.Index] = true,
                _ => false,
            };
            if (!valid)
            {
                throw new ArgumentException(
                    "The defect edit order contains an invalid or duplicate reference.",
                    nameof(request));
            }
        }
    }

    internal static void ValidateDefectSourceIdentity(
        int editCount,
        DevelopDefectSourceIdentity? identity)
    {
        if (editCount == 0)
        {
            if (identity is not null)
            {
                throw new ArgumentException(
                    "A defect source identity requires at least one defect edit.",
                    nameof(identity));
            }
            return;
        }
        if (identity is null || identity.ByteCount == 0 ||
            identity.Sha256 is not { Length: 64 } sha256 ||
            sha256.Any(character => character is not
                (>= '0' and <= '9') and not (>= 'a' and <= 'f')))
        {
            throw new ArgumentException(
                "A defect recipe requires a lowercase SHA-256 source identity.",
                nameof(identity));
        }
    }

    internal static void ValidateDefectRecipeIdentity(int editCount, string? sha256)
    {
        if (editCount == 0)
        {
            if (sha256 is not null)
            {
                throw new ArgumentException(
                    "A defect-free request cannot carry a Defects recipe identity.",
                    nameof(sha256));
            }
            return;
        }
        // Direct callers built before ABI v35 do not have this identity. They remain on
        // v34, where Defects raw-proxy caching stays disabled.
        if (sha256 is null)
        {
            return;
        }
        if (sha256 is not { Length: 64 } ||
            sha256.Any(character => character is not
                (>= '0' and <= '9') and not (>= 'a' and <= 'f')))
        {
            throw new ArgumentException(
                "A Defects recipe requires a lowercase SHA-256 identity.",
                nameof(sha256));
        }
    }

    internal static void ValidateDefectRecipeAppendPrefix(
        int editCount,
        string? sha256,
        int prefixEditCount)
    {
        if (sha256 is null && prefixEditCount == 0)
        {
            return;
        }
        if (sha256 is not { Length: 64 } ||
            sha256.Any(character => character is not
                (>= '0' and <= '9') and not (>= 'a' and <= 'f')) ||
            prefixEditCount <= 0 || prefixEditCount >= editCount)
        {
            throw new ArgumentException(
                "A Defects append prefix requires a lowercase SHA-256 identity and a proper ordered prefix.",
                nameof(sha256));
        }
    }
}
