using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.Data.Sqlite;

namespace Negaflow.Catalog;

/// <summary>
/// snapshot 과 SQLite row 사이의 투영입니다. 연결을 열지 않고 이미 열린 것만 받습니다.
/// </summary>
internal static class SqliteCatalogRows
{
    internal readonly record struct DesiredRow(string Id, long Position, byte[] Payload);

    internal static bool TryReadMetadata(
        SqliteConnection connection,
        out int catalogVersion,
        out int minimumReaderVersion,
        out string? activeRollId)
    {
        catalogVersion = 0;
        minimumReaderVersion = 0;
        activeRollId = null;

        // 나중에 붙은 컬럼은 예전 파일에 없습니다. 읽기는 READONLY 라 ALTER 로 붙일 수 없으니
        // 없으면 없는 대로 읽습니다 - 컬럼 하나 때문에 라이브러리 전체를 못 여는 일은
        // 없어야 합니다. 빠진 컬럼은 다음 쓰기가 CreateTables 에서 붙입니다.
        HashSet<string> columns = SqliteCatalogSchema.TableColumns(
            connection,
            SqliteCatalogSchema.MetadataTable);
        foreach (string required in SqliteCatalogSchema.RequiredMetadataColumns)
        {
            if (!columns.Contains(required))
            {
                return false;
            }
        }
        string activeRollSelector = columns.Contains("active_roll_id") ? "active_roll_id" : "NULL";

        using SqliteCommand command = connection.CreateCommand();
        command.CommandText = $"""
            SELECT catalog_version, minimum_reader_version, {activeRollSelector}
            FROM catalog_metadata WHERE singleton = 1
            """;
        using SqliteDataReader reader = command.ExecuteReader();
        if (!reader.Read())
        {
            return false;
        }
        catalogVersion = reader.GetInt32(0);
        minimumReaderVersion = reader.GetInt32(1);
        activeRollId = reader.IsDBNull(2) ? null : reader.GetString(2);
        return !reader.Read();
    }

    internal static void UpsertMetadata(SqliteConnection connection, CatalogSnapshot snapshot)
    {
        using SqliteCommand command = connection.CreateCommand();
        command.CommandText = """
            INSERT INTO catalog_metadata(
              singleton, catalog_version, minimum_reader_version, active_roll_id
            ) VALUES(1, $version, $reader, $activeRoll)
            ON CONFLICT(singleton) DO UPDATE SET
              catalog_version=excluded.catalog_version,
              minimum_reader_version=excluded.minimum_reader_version,
              active_roll_id=excluded.active_roll_id
            """;
        command.Parameters.AddWithValue("$version", snapshot.CatalogVersion);
        command.Parameters.AddWithValue("$reader", snapshot.MinimumReaderVersion);
        command.Parameters.AddWithValue(
            "$activeRoll",
            (object?)snapshot.ActiveRollId ?? DBNull.Value);
        command.ExecuteNonQuery();
    }

    internal static bool TryReadRows(
        SqliteConnection connection,
        CatalogEntityTable table,
        out IReadOnlyList<CatalogEntityRow> rows)
    {
        List<CatalogEntityRow> decoded = [];
        rows = decoded;
        // 뼈대 표는 한 줄이라도 못 읽으면 열지 않습니다. 부수 기록은 그 줄만 버립니다 -
        // 어느 쪽인지는 CatalogEntityTables.IsStrict 가 정합니다.
        bool strict = CatalogEntityTables.IsStrict(table);

        using SqliteCommand command = connection.CreateCommand();
        command.CommandText =
            $"SELECT id, payload FROM {CatalogEntityTables.SqlName(table)} ORDER BY position ASC";
        using SqliteDataReader reader = command.ExecuteReader();
        while (reader.Read())
        {
            if (reader.IsDBNull(0) || reader.IsDBNull(1))
            {
                if (strict)
                {
                    return false;
                }
                continue;
            }
            string id = reader.GetString(0);
            byte[] payload = (byte[])reader.GetValue(1);
            JsonNode? node;
            try
            {
                node = JsonNode.Parse(payload);
            }
            catch (JsonException)
            {
                if (strict)
                {
                    return false;
                }
                continue;
            }
            if (node is not JsonObject payloadObject || id.Length == 0)
            {
                if (strict)
                {
                    return false;
                }
                continue;
            }
            decoded.Add(new CatalogEntityRow(id, payloadObject));
        }
        return true;
    }

    internal static bool TryProject(
        IReadOnlyList<CatalogEntityRow> rows,
        out List<DesiredRow> projected)
    {
        projected = new List<DesiredRow>(rows.Count);
        HashSet<string> seen = new(StringComparer.Ordinal);
        for (int index = 0; index < rows.Count; index++)
        {
            CatalogEntityRow row = rows[index];
            if (row is null || string.IsNullOrEmpty(row.Id) || !seen.Add(row.Id))
            {
                return false;
            }
            projected.Add(new DesiredRow(
                row.Id,
                index,
                CatalogJson.SerializeCanonical(row.Payload)));
        }
        return true;
    }

    internal static void SynchronizeRows(
        SqliteConnection connection,
        CatalogEntityTable table,
        List<DesiredRow> desired)
    {
        string name = CatalogEntityTables.SqlName(table);
        Dictionary<string, long> existing = ReadPositions(connection, name);

        HashSet<string> desiredIds = new(desired.Count, StringComparer.Ordinal);
        foreach (DesiredRow row in desired)
        {
            desiredIds.Add(row.Id);
        }

        List<string> removed = [];
        foreach (KeyValuePair<string, long> entry in existing)
        {
            if (!desiredIds.Contains(entry.Key))
            {
                removed.Add(entry.Key);
            }
        }
        if (removed.Count > 0)
        {
            using SqliteCommand delete = connection.CreateCommand();
            delete.CommandText = $"DELETE FROM {name} WHERE id = $id";
            SqliteParameter deleteId = delete.Parameters.Add("$id", SqliteType.Text);
            foreach (string id in removed)
            {
                deleteId.Value = id;
                delete.ExecuteNonQuery();
            }
        }

        // position 은 UNIQUE 이므로 자리를 바꾸는 row 를 먼저 충돌하지 않는 범위로 밀어냅니다.
        // 자리가 그대로인 row 는 건드리지 않으므로 페이지를 다시 쓰지 않습니다.
        List<string> moved = [];
        foreach (DesiredRow row in desired)
        {
            if (existing.TryGetValue(row.Id, out long current) && current != row.Position)
            {
                moved.Add(row.Id);
            }
        }
        if (moved.Count > 0)
        {
            using SqliteCommand bump = connection.CreateCommand();
            bump.CommandText =
                $"UPDATE {name} SET position = position + $offset WHERE id = $id";
            bump.Parameters.AddWithValue("$offset", SqliteCatalogSchema.PositionRelocationOffset);
            SqliteParameter bumpId = bump.Parameters.Add("$id", SqliteType.Text);
            foreach (string id in moved)
            {
                bumpId.Value = id;
                bump.ExecuteNonQuery();
            }
        }

        if (desired.Count == 0)
        {
            return;
        }

        using SqliteCommand upsert = connection.CreateCommand();
        upsert.CommandText = $"""
            INSERT INTO {name}(id, position, payload) VALUES($id, $position, $payload)
            ON CONFLICT(id) DO UPDATE SET
              position=excluded.position,
              payload=excluded.payload
            WHERE {name}.position != excluded.position
               OR {name}.payload != excluded.payload
            """;
        SqliteParameter upsertId = upsert.Parameters.Add("$id", SqliteType.Text);
        SqliteParameter upsertPosition = upsert.Parameters.Add("$position", SqliteType.Integer);
        SqliteParameter upsertPayload = upsert.Parameters.Add("$payload", SqliteType.Blob);
        foreach (DesiredRow row in desired)
        {
            upsertId.Value = row.Id;
            upsertPosition.Value = row.Position;
            upsertPayload.Value = row.Payload;
            upsert.ExecuteNonQuery();
        }
    }

    internal static Dictionary<string, long> ReadPositions(
        SqliteConnection connection,
        string tableName)
    {
        Dictionary<string, long> positions = new(StringComparer.Ordinal);
        using SqliteCommand command = connection.CreateCommand();
        command.CommandText = $"SELECT id, position FROM {tableName}";
        using SqliteDataReader reader = command.ExecuteReader();
        while (reader.Read())
        {
            positions[reader.GetString(0)] = reader.GetInt64(1);
        }
        return positions;
    }
}
