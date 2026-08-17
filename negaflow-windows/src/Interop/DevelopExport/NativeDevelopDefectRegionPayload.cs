namespace Negaflow.Interop;

internal sealed record NativeDefectRegionPayload(
    NativeDefectRegionEditV1[] Edits,
    byte[] MaskBytes,
    NativeDefectInfraredEditV1[] InfraredEdits,
    byte[] InfraredAttenuationBytes,
    NativeDefectInfraredItemV1[] InfraredItems);

/// <summary>결함 영역·IR 네이티브 페이로드입니다.</summary>
internal static unsafe class NativeDevelopDefectRegionPayloadBuilder
{
    internal static NativeDefectRegionPayload BuildDefectRegionPayload(
        IReadOnlyList<DevelopDefectRegionEdit> source,
        IReadOnlyList<DevelopDefectInfraredEdit> infrared)
    {
        int totalBytes = 0;
        foreach (DevelopDefectRegionEdit edit in source)
        {
            totalBytes = checked(totalBytes + edit.Mask.Length);
        }
        int infraredClusterCount = 0;
        foreach (DevelopDefectInfraredEdit item in infrared)
        {
            infraredClusterCount = checked(infraredClusterCount + item.Clusters.Count);
            foreach (DevelopDefectInfraredCluster cluster in item.Clusters)
            {
                totalBytes = checked(totalBytes + cluster.CoreMask.Length);
            }
        }
        byte[] masks = new byte[totalBytes];
        NativeDefectRegionEditV1[] edits =
            new NativeDefectRegionEditV1[source.Count + infraredClusterCount];
        int offset = 0;
        for (int index = 0; index < source.Count; ++index)
        {
            DevelopDefectRegionEdit edit = source[index];
            edit.Mask.Span.CopyTo(masks.AsSpan(offset));
            double angle = edit.PreferredAngleDegrees ?? 0.0;
            edits[index] = new NativeDefectRegionEditV1
            {
                Enabled = edit.IsEnabled ? 1U : 0U,
                RoiX = edit.RoiX,
                RoiY = edit.RoiY,
                Width = edit.Width,
                Height = edit.Height,
                MaskStrideBytes = edit.MaskStrideBytes == 0U
                    ? edit.Width
                    : edit.MaskStrideBytes,
                MaskOffset = checked((uint)offset),
                MaskByteCount = checked((uint)edit.Mask.Length),
                Strength = edit.Strength,
                HasPreferredAngle = edit.PreferredAngleDegrees.HasValue ? 1U : 0U,
                PreferredAngleDegrees = angle,
            };
            offset = checked(offset + edit.Mask.Length);
        }

        int attenuationByteCount = 0;
        foreach (DevelopDefectInfraredEdit item in infrared)
        {
            foreach (DevelopDefectInfraredCluster cluster in item.Clusters)
            {
                if (cluster.AttenuationR16 is { } attenuation)
                {
                    attenuationByteCount = checked(
                        attenuationByteCount + attenuation.Length);
                }
            }
        }
        byte[] attenuationBytes = new byte[attenuationByteCount];
        NativeDefectInfraredEditV1[] infraredEdits =
            new NativeDefectInfraredEditV1[infraredClusterCount];
        NativeDefectInfraredItemV1[] infraredItems =
            new NativeDefectInfraredItemV1[infrared.Count];
        int attenuationOffset = 0;
        int clusterIndex = 0;
        for (int itemIndex = 0; itemIndex < infrared.Count; ++itemIndex)
        {
            DevelopDefectInfraredEdit item = infrared[itemIndex];
            infraredItems[itemIndex] = new NativeDefectInfraredItemV1
            {
                ClusterOffset = checked((uint)clusterIndex),
                ClusterCount = checked((uint)item.Clusters.Count),
            };
            foreach (DevelopDefectInfraredCluster cluster in item.Clusters)
            {
                cluster.CoreMask.Span.CopyTo(masks.AsSpan(offset));
                int regionIndex = checked(source.Count + clusterIndex);
                edits[regionIndex] = new NativeDefectRegionEditV1
                {
                    Enabled = item.IsEnabled ? 1U : 0U,
                    RoiX = cluster.RoiX,
                    RoiY = cluster.RoiY,
                    Width = cluster.Width,
                    Height = cluster.Height,
                    MaskStrideBytes = cluster.CoreMaskStrideBytes == 0U
                        ? cluster.Width
                        : cluster.CoreMaskStrideBytes,
                    MaskOffset = checked((uint)offset),
                    MaskByteCount = checked((uint)cluster.CoreMask.Length),
                    Strength = item.Strength,
                };
                offset = checked(offset + cluster.CoreMask.Length);

                if (cluster.AttenuationR16 is { } attenuation)
                {
                    attenuation.Span.CopyTo(
                        attenuationBytes.AsSpan(attenuationOffset));
                    infraredEdits[clusterIndex] = new NativeDefectInfraredEditV1
                    {
                        RegionEditIndex = checked((uint)regionIndex),
                        HasAttenuation = 1U,
                        AttenuationStrideBytes = cluster.AttenuationStrideBytes == 0U
                            ? checked(cluster.Width * sizeof(ushort))
                            : cluster.AttenuationStrideBytes,
                        AttenuationOffset = checked((uint)attenuationOffset),
                        AttenuationByteCount = checked((uint)attenuation.Length),
                    };
                    attenuationOffset = checked(
                        attenuationOffset + attenuation.Length);
                }
                else
                {
                    infraredEdits[clusterIndex] = new NativeDefectInfraredEditV1
                    {
                        RegionEditIndex = checked((uint)regionIndex),
                    };
                }
                ++clusterIndex;
            }
        }
        return new NativeDefectRegionPayload(
            edits, masks, infraredEdits, attenuationBytes, infraredItems);
    }
}
