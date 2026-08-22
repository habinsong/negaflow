using System.Text.Json;
using System.Text.Json.Serialization;
using Negaflow.Catalog;
using Negaflow.Interop;

namespace Negaflow.Shell.Library;

/// <summary>
/// persistent developed cache identity 의 recipe 바이트를 만듭니다.
///
/// 결함 마스크는 <see cref="DefectRecipeProjector"/> 가 저장된 zlib 마스크를 화소로 펼친 뒤라
/// 그대로 직렬화하면 전면 마스크 한 장이 5088x3401x4 바이트가 되고 base64 로 다시 4/3 배가
/// 됩니다. 실제 카탈로그의 frame 1 은 이 방식에서 recipe 하나가 276,880,606 바이트였고
/// 16MiB 상한을 넘겨 정착본이 영영 저장되지 않았습니다. 그래서 여기서는 마스크의 치수·stride·
/// 길이만 쓰고, 마스크 내용 자체는 catalog 가 이미 들고 있는 recipe revision 과 SHA-256 으로
/// 식별합니다. 이 경로는 SHA-256 을 새로 계산하지 않습니다.
/// </summary>
internal static class DevelopedPreviewCacheRecipeCodec
{
    /// <summary>실제 zlib sidecar 마스크는 이 예산 안에 넉넉히 들어옵니다.</summary>
    private const long VerbatimMaskBudgetBytes = 4L * 1024 * 1024;

    private static readonly JsonSerializerOptions Options = new()
    {
        WriteIndented = false,
        Converters =
        {
            new RegionEditConverter(),
            new InfraredClusterConverter(),
        },
    };

    internal static byte[] Compose(
        DevelopExportRequest request,
        DefectRecipeSnapshot? recipe) =>
        JsonSerializer.SerializeToUtf8Bytes(
            new CacheRecipe(
                request,
                recipe?.FingerprintVersion ?? 0,
                recipe?.RecipeRevision ?? 0UL,
                recipe?.RecipeSha256,
                recipe?.SourceIdentity?.ByteCount ?? 0UL,
                recipe?.SourceIdentity?.Sha256,
                StoredMasks(recipe)),
            Options);

    /// <summary>
    /// catalog 가 sidecar 에 들고 있는 그대로의 마스크입니다. 펼치기 전 상태라 전면 마스크 한 장이
    /// 화소본 69,217,152 바이트 대신 압축본 수십 KiB 이며, 그대로 비교하므로 fingerprint 가 마스크
    /// 내용을 덮지 않는 구간까지 정확히 닫습니다. 새 hash 는 만들지 않습니다.
    ///
    /// 압축하지 않고 저장된 전면 마스크까지 통째로 넣으면 recipe 가 다시 상한을 넘어 정착본이
    /// 저장되지 않으므로, 예산을 넘는 마스크는 길이만 남깁니다. 그 경우에도 모든 편집이
    /// <see cref="DefectRecipeSnapshot.RecipeRevision"/> 을 올리므로 바뀐 recipe 는 계속 miss 입니다.
    /// </summary>
    private static IReadOnlyList<StoredMask> StoredMasks(DefectRecipeSnapshot? recipe)
    {
        if (recipe is null)
        {
            return [];
        }
        List<StoredMask> masks = [];
        long remaining = VerbatimMaskBudgetBytes;
        foreach (DefectEditItem item in recipe.Items)
        {
            if (item.RegionMask is { } region)
            {
                masks.Add(Take(region, ref remaining));
            }
            foreach (DefectCluster cluster in item.Clusters ?? [])
            {
                masks.Add(Take(cluster.Mask, ref remaining));
                if (cluster.AttenuationR16 is { } attenuation)
                {
                    masks.Add(Take(attenuation, ref remaining));
                }
            }
        }
        return masks;
    }

    private static StoredMask Take(DefectMask mask, ref long remaining)
    {
        if (mask.Data.LongLength > remaining)
        {
            return new StoredMask(mask.IsZlib, mask.Data.LongLength, null);
        }
        remaining -= mask.Data.LongLength;
        return new StoredMask(mask.IsZlib, mask.Data.LongLength, mask.Data);
    }

    private sealed record StoredMask(bool Zlib, long Length, byte[]? Data);

    private sealed record CacheRecipe(
        DevelopExportRequest Request,
        int DefectFingerprintVersion,
        ulong DefectRecipeRevision,
        string? DefectRecipeSha256,
        ulong DefectSourceBytes,
        string? DefectSourceSha256,
        IReadOnlyList<StoredMask> DefectStoredMasks);

    private sealed class RegionEditConverter : JsonConverter<DevelopDefectRegionEdit>
    {
        public override DevelopDefectRegionEdit Read(
            ref Utf8JsonReader reader,
            Type typeToConvert,
            JsonSerializerOptions options) =>
            throw new NotSupportedException(
                "Cache identity recipe bytes are compared, never deserialized.");

        public override void Write(
            Utf8JsonWriter writer,
            DevelopDefectRegionEdit value,
            JsonSerializerOptions options)
        {
            writer.WriteStartObject();
            writer.WriteBoolean("enabled", value.IsEnabled);
            writer.WriteNumber("roiX", value.RoiX);
            writer.WriteNumber("roiY", value.RoiY);
            writer.WriteNumber("width", value.Width);
            writer.WriteNumber("height", value.Height);
            writer.WriteNumber("maskStride", value.MaskStrideBytes);
            writer.WriteNumber("maskLength", value.Mask.Length);
            writer.WriteNumber("strength", value.Strength);
            if (value.PreferredAngleDegrees is { } angle)
            {
                writer.WriteNumber("angle", angle);
            }
            else
            {
                writer.WriteNull("angle");
            }
            writer.WriteEndObject();
        }
    }

    private sealed class InfraredClusterConverter : JsonConverter<DevelopDefectInfraredCluster>
    {
        public override DevelopDefectInfraredCluster Read(
            ref Utf8JsonReader reader,
            Type typeToConvert,
            JsonSerializerOptions options) =>
            throw new NotSupportedException(
                "Cache identity recipe bytes are compared, never deserialized.");

        public override void Write(
            Utf8JsonWriter writer,
            DevelopDefectInfraredCluster value,
            JsonSerializerOptions options)
        {
            writer.WriteStartObject();
            writer.WriteNumber("roiX", value.RoiX);
            writer.WriteNumber("roiY", value.RoiY);
            writer.WriteNumber("width", value.Width);
            writer.WriteNumber("height", value.Height);
            writer.WriteNumber("coreStride", value.CoreMaskStrideBytes);
            writer.WriteNumber("coreLength", value.CoreMask.Length);
            writer.WriteNumber("attenuationStride", value.AttenuationStrideBytes);
            if (value.AttenuationR16 is { } attenuation)
            {
                writer.WriteNumber("attenuationLength", attenuation.Length);
            }
            else
            {
                writer.WriteNull("attenuationLength");
            }
            writer.WriteEndObject();
        }
    }
}
