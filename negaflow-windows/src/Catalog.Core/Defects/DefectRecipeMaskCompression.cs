using System.IO.Compression;

namespace Negaflow.Catalog;

/// <summary>
/// defect 마스크의 zlib 압축과 그 검사입니다. 무엇이 유효한 recipe 인지는
/// <see cref="DefectRecipeValidator"/> 가 정하고, 여기서는 바이트만 다룹니다.
/// </summary>
internal static class DefectRecipeMaskCompression
{
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
