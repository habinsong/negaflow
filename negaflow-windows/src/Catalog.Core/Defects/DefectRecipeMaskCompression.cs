using System.IO.Compression;

namespace Negaflow.Catalog;

/// <summary>
/// defect 마스크의 zlib 압축과 그 검사입니다. 무엇이 유효한 recipe 인지는
/// <see cref="DefectRecipeValidator"/> 가 정하고, 여기서는 바이트만 다룹니다.
/// </summary>
internal static class DefectRecipeMaskCompression
{
    private const long MinimumParallelRawBytes = 1L * 1_024 * 1_024;

    internal static IReadOnlyList<DefectEditItem> CompressRawMasks(
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
            if (item.RegionMask is { } region &&
                item.RegionWidth is { } regionWidth &&
                item.RegionHeight is { } regionHeight)
            {
                RequireRawSize(region, regionWidth, regionHeight, bytesPerPixel: 4);
            }
            DefectMask? regionMask = item.RegionMask is { } mask
                ? Compress(mask)
                : null;
            IReadOnlyList<DefectCluster>? clusters = item.Clusters is { } sourceClusters
                ? CompressClusters(sourceClusters)
                : null;
            copies[index] = item with
            {
                RegionMask = regionMask,
                Clusters = clusters,
            };
        }
        return copies;
    }

    private static IReadOnlyList<DefectCluster> CompressClusters(
        IReadOnlyList<DefectCluster> source)
    {
        DefectCluster[] compressed = new DefectCluster[source.Count];
        long rawBytes = 0L;
        foreach (DefectCluster cluster in source)
        {
            RequireRawSize(cluster.Mask, cluster.Width, cluster.Height, bytesPerPixel: 4);
            if (cluster.AttenuationR16 is { } attenuation)
            {
                RequireRawSize(attenuation, cluster.Width, cluster.Height, bytesPerPixel: 2);
            }
            rawBytes += cluster.Mask.Data.LongLength;
            rawBytes += cluster.AttenuationR16?.Data.LongLength ?? 0L;
        }
        if (source.Count > 1 && rawBytes >= MinimumParallelRawBytes &&
            Environment.ProcessorCount > 1)
        {
            Parallel.For(
                0,
                source.Count,
                new ParallelOptions
                {
                    MaxDegreeOfParallelism = Math.Min(
                        Environment.ProcessorCount,
                        source.Count),
                },
                index => compressed[index] = CompressCluster(source[index]));
        }
        else
        {
            for (int index = 0; index < source.Count; ++index)
            {
                compressed[index] = CompressCluster(source[index]);
            }
        }
        return compressed;
    }

    private static DefectCluster CompressCluster(DefectCluster cluster) =>
        cluster with
        {
            Mask = Compress(cluster.Mask),
            AttenuationR16 = cluster.AttenuationR16 is { } attenuation
                ? Compress(attenuation)
                : null,
        };

    /// <summary>
    /// 압축 전 원본은 폭 × 높이 × 화소당 바이트여야 합니다(마스크 4, 적외선 감쇠 창 2). 압축부터
    /// 하면 틀린 크기도 받아들이고 읽을 때에야 거부해, 기록이 저장되지 않습니다 — macOS 1.1.8
    /// <c>checkAttenuationShape</c> 도 만들 때 봅니다. 폭·높이 자체가 틀린 것은 검증기가 거부합니다.
    /// </summary>
    private static void RequireRawSize(DefectMask mask, int width, int height, int bytesPerPixel)
    {
        if (mask.Data is { } data && !mask.IsZlib && width > 0 && height > 0 &&
            data.LongLength != (long)width * height * bytesPerPixel)
        {
            throw new InvalidDataException("Defects mask size does not match its dimensions.");
        }
    }

    internal static DefectMask Compress(DefectMask mask)
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

    internal static bool HasExactZlibOutput(byte[] data, long expectedBytes)
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
}
