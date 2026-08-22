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
    /// <summary>
    /// 방금 만든 페이로드입니다. 레시피 지문이 같으면 그대로 다시 씁니다.
    /// </summary>
    /// <remarks>
    /// **이것을 렌더마다 새로 만들고 있었습니다.** 결함 마스크는 원본 해상도라
    /// 한 장이 수십 MB 이고, 아래 조립은 그 전부를 새 배열에 복사합니다. 실측:
    /// 결함 7층이 걸린 frame_1 에서 네이티브 렌더는 21ms 인데 `Preview` 호출은
    /// 76~92ms 였습니다 — 차이가 전부 이 복사였습니다. 8ms 간격 드래그에서 초당
    /// 수백 MB 를 복사하고 곧바로 GC 로 버린 셈입니다.
    ///
    /// 열쇠는 **순서까지 포함한 레시피 SHA-256** 입니다. 마스크가 한 화소라도 바뀌면
    /// 지문이 바뀌므로 옛 페이로드를 쓸 길이 없습니다. 지문이 없는 legacy 요청은
    /// 그대로 매번 조립합니다.
    ///
    /// 자리를 둘 두는 이유 — 인터랙티브와 정착이 같은 레시피를 쓰므로 하나로도 되지만,
    /// 이웃 예열이 배경에서 다른 사진을 돌립니다.
    /// </remarks>
    private sealed record CachedPayload(
        string RecipeSha256,
        int RegionCount,
        int InfraredCount,
        NativeDefectRegionPayload Payload);

    private static readonly Lock CacheGate = new();
    private static readonly CachedPayload?[] Cache = new CachedPayload?[2];
    private static int cacheNext;

    internal static NativeDefectRegionPayload BuildDefectRegionPayload(
        IReadOnlyList<DevelopDefectRegionEdit> source,
        IReadOnlyList<DevelopDefectInfraredEdit> infrared,
        string? recipeSha256)
    {
        if (recipeSha256 is { Length: > 0 })
        {
            lock (CacheGate)
            {
                foreach (CachedPayload? entry in Cache)
                {
                    if (entry is not null &&
                        string.Equals(
                            entry.RecipeSha256, recipeSha256, StringComparison.Ordinal) &&
                        entry.RegionCount == source.Count &&
                        entry.InfraredCount == infrared.Count)
                    {
                        return entry.Payload;
                    }
                }
            }
        }
        NativeDefectRegionPayload built = BuildDefectRegionPayloadUncached(source, infrared);
        if (recipeSha256 is { Length: > 0 })
        {
            lock (CacheGate)
            {
                Cache[cacheNext] = new CachedPayload(
                    recipeSha256, source.Count, infrared.Count, built);
                cacheNext = (cacheNext + 1) % Cache.Length;
            }
        }
        return built;
    }

    private static NativeDefectRegionPayload BuildDefectRegionPayloadUncached(
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
