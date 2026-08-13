using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Negaflow.Catalog;

/// <summary>
/// 한 frame 에 저장된 현상 버전입니다. macOS <c>DevelopSnapshot</c> 과 같은 자리이며 키 이름도
/// 같습니다 — <c>developSnapshots</c> 의 <c>id</c>/<c>name</c>/<c>createdAt</c>/<c>presetID</c>.
/// </summary>
/// <remarks>
/// recipe 본문(<c>params</c>)은 여기서 해석하지 않습니다. macOS 는 현상 파라미터 전체를 통째로
/// 담고, Windows 도 원본 JSON 을 그대로 보관했다가 복원할 때 그대로 되돌립니다. 필드를 다시
/// 모델링하면 recipe 가 늘어날 때마다 버전 저장이 조용히 뒤처집니다.
/// </remarks>
public sealed record LibraryVersionSnapshot(
    string Id,
    string Name,
    DateTimeOffset? CreatedAt,
    string? PresetId);

public static class LibraryVersions
{
    internal const string VersionsName = "developSnapshots";
    internal const string VersionIdName = "id";
    internal const string VersionNameName = "name";
    internal const string VersionCreatedAtName = "createdAt";
    internal const string VersionPresetIdName = "presetID";
    internal const string VersionParametersName = "params";

    /// <summary>macOS 와 같이 이름은 비어 있을 수 없고 지나치게 길지도 않습니다.</summary>
    public const int MaximumNameLength = 120;

    public static bool TryRead(JsonElement frameRecord, out IReadOnlyList<LibraryVersionSnapshot> versions)
    {
        versions = [];
        if (!frameRecord.TryGetProperty(VersionsName, out JsonElement element) ||
            element.ValueKind == JsonValueKind.Null)
        {
            return true;
        }
        if (element.ValueKind != JsonValueKind.Array)
        {
            return false;
        }

        List<LibraryVersionSnapshot> read = [];
        HashSet<string> seen = new(StringComparer.Ordinal);
        foreach (JsonElement entry in element.EnumerateArray())
        {
            if (entry.ValueKind != JsonValueKind.Object ||
                !entry.TryGetProperty(VersionIdName, out JsonElement idElement) ||
                idElement.ValueKind != JsonValueKind.String ||
                idElement.GetString() is not { Length: > 0 } id ||
                !seen.Add(id))
            {
                return false;
            }
            if (!entry.TryGetProperty(VersionNameName, out JsonElement nameElement) ||
                nameElement.ValueKind != JsonValueKind.String ||
                nameElement.GetString() is not { Length: > 0 } name)
            {
                return false;
            }
            // recipe 본문이 없는 버전은 복원할 수 없으므로 목록에 올리지 않습니다.
            if (!entry.TryGetProperty(VersionParametersName, out JsonElement parameters) ||
                parameters.ValueKind != JsonValueKind.Object)
            {
                return false;
            }
            read.Add(new LibraryVersionSnapshot(
                id,
                name,
                ReadCreatedAt(entry),
                ReadPresetId(entry)));
        }
        versions = read;
        return true;
    }

    /// <summary>지금 recipe 를 새 버전으로 담습니다. 기존 버전은 건드리지 않습니다.</summary>
    public static LibraryFrameWriteResult Capture(
        JsonObject frameRecord,
        string versionId,
        string name,
        DateTimeOffset createdAt)
    {
        ArgumentNullException.ThrowIfNull(frameRecord);
        if (string.IsNullOrWhiteSpace(versionId) ||
            string.IsNullOrWhiteSpace(name) ||
            name.Length > MaximumNameLength)
        {
            return LibraryFrameWriteResult.Failure(LibraryFrameError.InvalidVersion);
        }
        if (frameRecord[VersionParametersName] is not JsonObject parameters)
        {
            return LibraryFrameWriteResult.Failure(LibraryFrameError.MissingParameters);
        }

        JsonObject updated = frameRecord.DeepClone().AsObject();
        JsonArray versions = ExistingVersions(updated);
        foreach (JsonNode? existing in versions)
        {
            if (existing is JsonObject entry &&
                entry[VersionIdName]?.GetValue<string>() == versionId)
            {
                return LibraryFrameWriteResult.Failure(LibraryFrameError.InvalidVersion);
            }
        }

        versions.Add(new JsonObject
        {
            [VersionIdName] = versionId,
            [VersionNameName] = name.Trim(),
            [VersionCreatedAtName] = createdAt.ToString("O", CultureInfo.InvariantCulture),
            [VersionPresetIdName] = updated["presetID"]?.DeepClone(),
            [VersionParametersName] = parameters.DeepClone(),
        });
        updated[VersionsName] = versions;
        return LibraryFrameWriteResult.Success(updated);
    }

    /// <summary>
    /// 담아 둔 recipe 를 그대로 되돌립니다. 버전 목록 자체는 남으므로 되돌린 뒤에도 다른
    /// 버전으로 다시 갈 수 있습니다.
    /// </summary>
    public static LibraryFrameWriteResult Restore(JsonObject frameRecord, string versionId)
    {
        ArgumentNullException.ThrowIfNull(frameRecord);
        if (string.IsNullOrWhiteSpace(versionId))
        {
            return LibraryFrameWriteResult.Failure(LibraryFrameError.InvalidVersion);
        }

        JsonObject updated = frameRecord.DeepClone().AsObject();
        // 되돌리기는 목록을 읽기만 합니다. 떼어내면 되돌린 뒤 버전이 사라집니다.
        if (updated[VersionsName] is not JsonArray stored_versions)
        {
            return LibraryFrameWriteResult.Failure(LibraryFrameError.MissingVersion);
        }
        foreach (JsonNode? node in stored_versions)
        {
            if (node is not JsonObject entry ||
                entry[VersionIdName]?.GetValue<string>() != versionId)
            {
                continue;
            }
            if (entry[VersionParametersName] is not JsonObject storedParameters)
            {
                return LibraryFrameWriteResult.Failure(LibraryFrameError.InvalidVersion);
            }
            updated[VersionParametersName] = storedParameters.DeepClone();
            updated["presetID"] = entry[VersionPresetIdName]?.DeepClone();
            return LibraryFrameWriteResult.Success(updated);
        }
        return LibraryFrameWriteResult.Failure(LibraryFrameError.MissingVersion);
    }

    public static LibraryFrameWriteResult Delete(JsonObject frameRecord, string versionId)
    {
        ArgumentNullException.ThrowIfNull(frameRecord);
        JsonObject updated = frameRecord.DeepClone().AsObject();
        JsonArray versions = ExistingVersions(updated);
        for (int index = 0; index < versions.Count; ++index)
        {
            if (versions[index] is JsonObject entry &&
                entry[VersionIdName]?.GetValue<string>() == versionId)
            {
                versions.RemoveAt(index);
                updated[VersionsName] = versions;
                return LibraryFrameWriteResult.Success(updated);
            }
        }
        return LibraryFrameWriteResult.Failure(LibraryFrameError.MissingVersion);
    }

    private static JsonArray ExistingVersions(JsonObject frameRecord)
    {
        if (frameRecord[VersionsName] is JsonArray existing)
        {
            // 원본에서 떼어내야 다른 노드의 부모로 다시 붙일 수 있습니다.
            frameRecord.Remove(VersionsName);
            return existing;
        }
        return [];
    }

    private static DateTimeOffset? ReadCreatedAt(JsonElement entry)
    {
        if (!entry.TryGetProperty(VersionCreatedAtName, out JsonElement element))
        {
            return null;
        }
        if (element.ValueKind == JsonValueKind.String &&
            DateTimeOffset.TryParse(
                element.GetString(),
                CultureInfo.InvariantCulture,
                DateTimeStyles.RoundtripKind,
                out DateTimeOffset parsed))
        {
            return parsed;
        }
        // Swift 는 기준 시각 2001-01-01 UTC 의 초 단위 실수로도 씁니다.
        return element.ValueKind == JsonValueKind.Number && element.TryGetDouble(out double seconds) &&
            double.IsFinite(seconds)
            ? new DateTimeOffset(2001, 1, 1, 0, 0, 0, TimeSpan.Zero).AddSeconds(seconds)
            : null;
    }

    private static string? ReadPresetId(JsonElement entry) =>
        entry.TryGetProperty(VersionPresetIdName, out JsonElement element) &&
        element.ValueKind == JsonValueKind.String
            ? element.GetString()
            : null;
}
