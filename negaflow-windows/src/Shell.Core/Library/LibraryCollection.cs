using System.Text.Json.Nodes;
using Negaflow.Catalog;

namespace Negaflow.Shell;

/// <summary>
/// 사용자가 손으로 모은 사진 묶음입니다. macOS <c>LibraryManualCollection</c> 과 같은 세 필드이며
/// 같은 catalog 표(<c>manual_collections</c>)에 삽니다.
/// </summary>
public sealed record LibraryCollectionSnapshot(
    string Id,
    string Name,
    IReadOnlyList<string> FrameIds)
{
    public const int MaximumNameBytes = 512;

    public static string? NormalizeName(string? value)
    {
        string trimmed = (value ?? string.Empty).Trim();
        return trimmed.Length == 0 ||
            System.Text.Encoding.UTF8.GetByteCount(trimmed) > MaximumNameBytes
            ? null
            : trimmed;
    }
}

internal static class LibraryCollectionRecord
{
    private const string IdName = "id";
    private const string NameName = "name";
    private const string FrameIdsName = "frameIDs";

    public static bool TryRead(CatalogEntityRow row, out LibraryCollectionSnapshot collection)
    {
        collection = default!;
        if (string.IsNullOrWhiteSpace(row.Id) ||
            row.Payload[IdName]?.GetValue<string>() is not { } payloadId ||
            !string.Equals(row.Id, payloadId, StringComparison.Ordinal) ||
            row.Payload[NameName]?.GetValue<string>() is not { } rawName ||
            LibraryCollectionSnapshot.NormalizeName(rawName) is not { } name)
        {
            return false;
        }
        var frameIds = new List<string>();
        if (row.Payload[FrameIdsName] is JsonArray array)
        {
            foreach (JsonNode? item in array)
            {
                // 목록 안의 한 칸이라도 모양이 다르면 카탈로그가 손상됐다는 뜻입니다. 조용히
                // 건너뛰면 사용자에게는 사진이 묶음에서 사라진 것으로 보입니다.
                if (item?.GetValue<string>() is not { } frameId ||
                    string.IsNullOrWhiteSpace(frameId))
                {
                    return false;
                }
                frameIds.Add(frameId);
            }
        }
        collection = new LibraryCollectionSnapshot(row.Id, name, frameIds);
        return true;
    }

    public static CatalogEntityRow Write(LibraryCollectionSnapshot collection)
    {
        var frameIds = new JsonArray();
        foreach (string frameId in collection.FrameIds)
        {
            frameIds.Add(frameId);
        }
        return new CatalogEntityRow(
            collection.Id,
            new JsonObject
            {
                [IdName] = collection.Id,
                [NameName] = collection.Name,
                [FrameIdsName] = frameIds,
            });
    }
}
