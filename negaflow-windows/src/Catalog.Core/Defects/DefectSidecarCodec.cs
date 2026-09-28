using System.Text.Json;
using System.Text.Json.Nodes;

namespace Negaflow.Catalog;

internal static class DefectSidecarCodec
{
    public const int CurrentVersion = 2;

    public static byte[] Serialize(DefectRecipeSnapshot snapshot)
    {
        ArgumentNullException.ThrowIfNull(snapshot);
        return CatalogJson.SerializeCanonical(new JsonObject
        {
            ["version"] = CurrentVersion,
            ["frameID"] = snapshot.FrameId.ToString("D"),
            ["fingerprintVersion"] = snapshot.FingerprintVersion,
            ["recipeRevision"] = JsonValue.Create(snapshot.RecipeRevision),
            ["recipeSHA256"] = snapshot.RecipeSha256,
            ["sourceIdentity"] = DefectSidecarEncoder.EncodeSourceIdentity(snapshot.SourceIdentity),
            ["items"] = DefectSidecarEncoder.EncodeItems(snapshot.Items),
        });
    }

    /// <summary>중복 키는 파싱에서 거절합니다 - <see cref="DefectSidecarDecoder"/> 참고.</summary>
    private static readonly JsonDocumentOptions StrictDocument = new()
    {
        AllowDuplicateProperties = false,
    };

    public static DefectSidecarReadResult Decode(
        ReadOnlyMemory<byte> data,
        Guid expectedFrameId,
        bool validateCompressedMasks = false)
    {
        try
        {
            using JsonDocument document = JsonDocument.Parse(data, StrictDocument);
            JsonElement root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object ||
                !DefectSidecarDecoder.TryInt32(
                    DefectSidecarDecoder.Property(root, "version"),
                    out int version))
            {
                return DefectSidecarReadResult.Failure(
                    DefectSidecarError.InvalidContent);
            }
            if (version != CurrentVersion)
            {
                return DefectSidecarReadResult.Failure(
                    DefectSidecarError.UnsupportedVersion,
                    version);
            }
            if (!DefectSidecarDecoder.HasExactProperties(
                    root,
                    "version",
                    "frameID",
                    "fingerprintVersion",
                    "recipeRevision",
                    "recipeSHA256",
                    "sourceIdentity",
                    "items") ||
                !DefectSidecarDecoder.TryString(
                    DefectSidecarDecoder.Property(root, "frameID"),
                    out string? frameText) ||
                !Guid.TryParseExact(frameText, "D", out Guid frameId) ||
                !DefectSidecarDecoder.TryInt32(
                    DefectSidecarDecoder.Property(root, "fingerprintVersion"),
                    out int fingerprintVersion) ||
                !DefectSidecarDecoder.TryUInt64(
                    DefectSidecarDecoder.Property(root, "recipeRevision"),
                    out ulong recipeRevision) ||
                !DefectSidecarDecoder.TryString(
                    DefectSidecarDecoder.Property(root, "recipeSHA256"),
                    out string? recipeSha256) ||
                !DefectSidecarDecoder.TryReadSourceIdentity(
                    DefectSidecarDecoder.Property(root, "sourceIdentity"),
                    out DefectSourceIdentity? sourceIdentity) ||
                DefectSidecarDecoder.Property(root, "items") is not
                    { ValueKind: JsonValueKind.Array } itemNodes ||
                itemNodes.GetArrayLength() > DefectRecipeValidator.MaximumItems ||
                !DefectSidecarDecoder.TryReadItems(itemNodes, out IReadOnlyList<DefectEditItem> items) ||
                !DefectRecipeValidator.TryCreateDecodedSnapshot(
                    expectedFrameId,
                    frameId,
                    fingerprintVersion,
                    recipeRevision,
                    recipeSha256,
                    sourceIdentity,
                    items,
                    validateCompressedMasks,
                    out DefectRecipeSnapshot snapshot))
            {
                return DefectSidecarReadResult.Failure(
                    DefectSidecarError.InvalidContent,
                    version);
            }
            return DefectSidecarReadResult.Success(snapshot);
        }
        catch (Exception error) when (error is
            JsonException or FormatException or OverflowException or ArgumentException)
        {
            return DefectSidecarReadResult.Failure(
                DefectSidecarError.InvalidContent);
        }
    }

    public static bool AreSameSnapshot(
        DefectRecipeSnapshot left,
        DefectRecipeSnapshot right) =>
        Serialize(left).AsSpan().SequenceEqual(Serialize(right));

    public static bool HaveSameItems(
        DefectRecipeSnapshot left,
        DefectRecipeSnapshot right) =>
        CatalogJson.SerializeCanonical(DefectSidecarEncoder.EncodeItems(left.Items)).AsSpan()
            .SequenceEqual(CatalogJson.SerializeCanonical(DefectSidecarEncoder.EncodeItems(right.Items)));

}
