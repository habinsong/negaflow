using System.Globalization;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Negaflow.Catalog;

/// <summary>
/// backup 이 디스크에 남기는 JSON 형식입니다. 알 수 없는 필드가 하나라도 있으면 실패로
/// 봅니다 - 모르는 것을 무시하고 복원하면 무엇을 잃었는지 알 수 없게 됩니다.
/// </summary>
internal static class CatalogBackupCodec
{
    internal static byte[] SerializeCatalog(CatalogSnapshot snapshot)
    {
        JsonObject entities = [];
        foreach (CatalogEntityTable table in CatalogEntityTables.All)
        {
            JsonArray rows = [];
            foreach (CatalogEntityRow row in snapshot.Rows(table))
            {
                rows.Add(new JsonObject
                {
                    ["id"] = row.Id,
                    ["payload"] = row.Payload.DeepClone(),
                });
            }
            entities[CatalogEntityTables.SqlName(table)] = rows;
        }

        JsonObject root = new()
        {
            ["version"] = snapshot.CatalogVersion,
            ["minimumReaderVersion"] = snapshot.MinimumReaderVersion,
            ["activeRollId"] = snapshot.ActiveRollId,
            ["entities"] = entities,
        };
        return CatalogJson.SerializeCanonical(root);
    }

    internal static bool TryDeserializeCatalog(byte[] data, out CatalogSnapshot snapshot)
    {
        snapshot = null!;
        try
        {
            if (JsonNode.Parse(data) is not JsonObject root ||
                !HasExactProperties(
                    root,
                    "version",
                    "minimumReaderVersion",
                    "activeRollId",
                    "entities") ||
                !TryInt32(root["version"], out int version) ||
                !TryInt32(root["minimumReaderVersion"], out int minimumReaderVersion) ||
                version != CatalogSnapshot.CurrentCatalogVersion ||
                minimumReaderVersion != CatalogSnapshot.OldestReaderVersion ||
                root["entities"] is not JsonObject entities ||
                entities.Count != CatalogEntityTables.All.Count)
            {
                return false;
            }

            string? activeRollId = null;
            if (root["activeRollId"] is JsonNode activeNode &&
                (activeNode is not JsonValue activeValue ||
                 !activeValue.TryGetValue(out activeRollId)))
            {
                return false;
            }

            Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>> tables = [];
            foreach (CatalogEntityTable table in CatalogEntityTables.All)
            {
                string tableName = CatalogEntityTables.SqlName(table);
                if (entities[tableName] is not JsonArray rows)
                {
                    return false;
                }

                HashSet<string> ids = new(StringComparer.Ordinal);
                List<CatalogEntityRow> decodedRows = [];
                foreach (JsonNode? node in rows)
                {
                    if (node is not JsonObject row ||
                        !HasExactProperties(row, "id", "payload") ||
                        row["id"] is not JsonValue idValue ||
                        !idValue.TryGetValue(out string? id) ||
                        string.IsNullOrWhiteSpace(id) ||
                        !ids.Add(id) ||
                        row["payload"] is not JsonObject payload)
                    {
                        return false;
                    }
                    _ = CatalogJson.SerializeCanonical(payload);
                    decodedRows.Add(new CatalogEntityRow(
                        id,
                        (JsonObject)payload.DeepClone()));
                }
                tables[table] = decodedRows;
            }
            if (entities.Any(property =>
                !CatalogEntityTables.All.Any(table => string.Equals(
                    CatalogEntityTables.SqlName(table),
                    property.Key,
                    StringComparison.Ordinal))))
            {
                return false;
            }

            snapshot = new CatalogSnapshot(
                version,
                minimumReaderVersion,
                activeRollId,
                tables);
            return true;
        }
        catch (JsonException)
        {
            return false;
        }
    }

    internal static byte[] SerializeManifest(CatalogBackupManifest manifest)
    {
        JsonArray defectIds = [];
        foreach (string id in manifest.DefectFrameIds)
        {
            defectIds.Add(id);
        }
        JsonArray files = [];
        foreach (CatalogBackupFileRecord file in manifest.Files
            .OrderBy(value => value.RelativePath, StringComparer.Ordinal))
        {
            files.Add(new JsonObject
            {
                ["relativePath"] = file.RelativePath,
                ["byteCount"] = file.ByteCount,
                ["sha256"] = file.Sha256,
            });
        }
        return CatalogJson.SerializeCanonical(new JsonObject
        {
            ["version"] = manifest.Version,
            ["sequence"] = manifest.Sequence,
            ["createdAt"] = manifest.CreatedAt.ToUniversalTime()
                .ToString("O", CultureInfo.InvariantCulture),
            ["frameCount"] = manifest.FrameCount,
            ["defectFrameIDs"] = defectIds,
            ["catalogVersion"] = manifest.CatalogVersion,
            ["files"] = files,
        });
    }

    internal static bool TryDeserializeManifest(
        byte[] data,
        out CatalogBackupManifest manifest)
    {
        manifest = null!;
        try
        {
            if (JsonNode.Parse(data) is not JsonObject root ||
                !HasExactProperties(
                    root,
                    "version",
                    "sequence",
                    "createdAt",
                    "frameCount",
                    "defectFrameIDs",
                    "catalogVersion",
                    "files") ||
                !TryInt32(root["version"], out int version) ||
                root["sequence"] is not JsonValue sequenceValue ||
                !sequenceValue.TryGetValue(out ulong sequence) ||
                root["createdAt"] is not JsonValue createdValue ||
                !createdValue.TryGetValue(out string? createdText) ||
                !DateTimeOffset.TryParse(
                    createdText,
                    CultureInfo.InvariantCulture,
                    DateTimeStyles.RoundtripKind,
                    out DateTimeOffset createdAt) ||
                !TryInt32(root["frameCount"], out int frameCount) ||
                frameCount < 0 ||
                !TryInt32(root["catalogVersion"], out int catalogVersion) ||
                root["defectFrameIDs"] is not JsonArray defectNodes ||
                root["files"] is not JsonArray fileNodes)
            {
                return false;
            }

            List<string> defectIds = [];
            foreach (JsonNode? node in defectNodes)
            {
                if (node is not JsonValue value ||
                    !value.TryGetValue(out string? id) ||
                    string.IsNullOrWhiteSpace(id))
                {
                    return false;
                }
                defectIds.Add(id);
            }
            if (!defectIds.SequenceEqual(
                    defectIds.OrderBy(value => value, StringComparer.Ordinal)) ||
                defectIds.Distinct(StringComparer.Ordinal).Count() != defectIds.Count)
            {
                return false;
            }

            List<CatalogBackupFileRecord> files = [];
            foreach (JsonNode? node in fileNodes)
            {
                if (node is not JsonObject file ||
                    !HasExactProperties(file, "relativePath", "byteCount", "sha256") ||
                    file["relativePath"] is not JsonValue pathValue ||
                    !pathValue.TryGetValue(out string? relativePath) ||
                    string.IsNullOrWhiteSpace(relativePath) ||
                    Path.IsPathRooted(relativePath) ||
                    relativePath.Contains("..", StringComparison.Ordinal) ||
                    file["byteCount"] is not JsonValue byteValue ||
                    !byteValue.TryGetValue(out long byteCount) ||
                    byteCount < 0 ||
                    file["sha256"] is not JsonValue hashValue ||
                    !hashValue.TryGetValue(out string? sha256) ||
                    sha256.Length != 64 ||
                    sha256.Any(character => !Uri.IsHexDigit(character)))
                {
                    return false;
                }
                files.Add(new CatalogBackupFileRecord(
                    relativePath,
                    byteCount,
                    sha256.ToLowerInvariant()));
            }
            if (!files.SequenceEqual(files.OrderBy(
                    value => value.RelativePath,
                    StringComparer.Ordinal)))
            {
                return false;
            }

            manifest = new CatalogBackupManifest(
                version,
                sequence,
                createdAt,
                frameCount,
                defectIds,
                catalogVersion,
                files);
            return true;
        }
        catch (JsonException)
        {
            return false;
        }
    }

    internal static bool HasExactProperties(JsonObject value, params string[] names)
    {
        if (value.Count != names.Length)
        {
            return false;
        }
        HashSet<string> expected = new(names, StringComparer.Ordinal);
        return value.All(property => expected.Contains(property.Key));
    }

    internal static bool TryInt32(JsonNode? node, out int value)
    {
        value = 0;
        return node is JsonValue jsonValue && jsonValue.TryGetValue(out value);
    }

    internal static bool TryGetDefectFrameIds(
        CatalogSnapshot snapshot,
        out IReadOnlyList<string> ids)
    {
        List<string> values = [];
        foreach (CatalogEntityRow frame in snapshot.Rows(CatalogEntityTable.Frames))
        {
            if (!frame.Payload.TryGetPropertyValue("hasDefectEdits", out JsonNode? node) ||
                node is null)
            {
                continue;
            }
            if (node is not JsonValue value || !value.TryGetValue(out bool hasEdits))
            {
                ids = [];
                return false;
            }
            if (hasEdits)
            {
                values.Add(frame.Id);
            }
        }
        ids = values.OrderBy(value => value, StringComparer.Ordinal).ToArray();
        return true;
    }
}
