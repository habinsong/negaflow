using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.Data.Sqlite;

namespace Negaflow.Catalog;

/// <summary>
/// primary catalog 의 유일한 SQLite 입구입니다. macOS <c>LibraryCatalogSQLiteStore</c> 의 table 배치와
/// PRAGMA 규율을 그대로 옮기되, 번호 공간과 실패 분류는 Windows 것입니다. ADR-0025 를 보십시오.
/// </summary>
/// <remarks>
/// 이 형식은 의도적으로 <c>internal</c> 입니다. 프로세스 lock 없이 카탈로그를 여는 경로가 존재하면
/// 단일 작성자 계약이 호출자의 규율에만 의존하게 됩니다. 외부에서 쓸 수 있는 입구는
/// <see cref="CatalogSession"/> 하나이고, 그것은 lock 을 잡지 않으면 만들어지지 않습니다.
/// <see cref="CatalogRecovery"/> 만 예외이며, 그쪽은 읽기조차 하지 않는 값싼 확인입니다.
/// </remarks>
internal static class SqliteCatalogStore
{
    /// <summary>물리 schema version. <c>PRAGMA user_version</c> 에 기록합니다.</summary>
    public const int StorageSchemaVersion = 1;

    /// <summary>
    /// position 을 다시 매길 때 쓰는 임시 오프셋입니다. <c>position</c> 이 UNIQUE 이므로 옮겨야 하는
    /// row 를 먼저 이 범위로 밀어내지 않으면 재배치 도중 제약을 어깁니다.
    /// </summary>
    private const long PositionRelocationOffset = 1L << 40;

    private const int SqliteBusy = 5;
    private const int SqliteLocked = 6;
    private const int SqliteReadOnly = 8;
    private const int SqliteCantOpen = 14;

    public static CatalogReadResult Read(string catalogPath)
    {
        if (string.IsNullOrWhiteSpace(catalogPath) || !Path.IsPathFullyQualified(catalogPath))
        {
            return CatalogReadResult.Failure(CatalogStoreError.InvalidPath);
        }
        if (!File.Exists(catalogPath))
        {
            return CatalogReadResult.Failure(CatalogStoreError.NotFound);
        }
        if (StoragePathPolicy.IsExistingReparsePoint(catalogPath))
        {
            return CatalogReadResult.Failure(CatalogStoreError.InvalidPath);
        }

        try
        {
            using SqliteConnection connection = OpenConnection(
                catalogPath,
                SqliteOpenMode.ReadOnly);
            if (!IsIntegral(connection))
            {
                return CatalogReadResult.Failure(CatalogStoreError.CorruptDatabase);
            }

            long storageVersion = ScalarInt64(connection, "PRAGMA user_version");
            if (storageVersion != StorageSchemaVersion)
            {
                return CatalogReadResult.Failure(
                    CatalogStoreError.UnsupportedStorageVersion,
                    (int)storageVersion);
            }

            if (!TryReadMetadata(
                    connection,
                    out int catalogVersion,
                    out int minimumReaderVersion,
                    out string? activeRollId))
            {
                return CatalogReadResult.Failure(CatalogStoreError.MalformedContent);
            }
            if (catalogVersion != CatalogSnapshot.CurrentCatalogVersion ||
                minimumReaderVersion != CatalogSnapshot.OldestReaderVersion)
            {
                return CatalogReadResult.Failure(
                    CatalogStoreError.UnsupportedCatalogVersion,
                    catalogVersion);
            }

            Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>> tables = [];
            foreach (CatalogEntityTable table in CatalogEntityTables.All)
            {
                if (!TryReadRows(connection, table, out IReadOnlyList<CatalogEntityRow>? rows))
                {
                    return CatalogReadResult.Failure(CatalogStoreError.MalformedContent);
                }
                tables[table] = rows;
            }

            return CatalogReadResult.Success(new CatalogSnapshot(
                catalogVersion,
                minimumReaderVersion,
                activeRollId,
                tables));
        }
        catch (SqliteException error)
        {
            return CatalogReadResult.Failure(ClassifySqlite(error));
        }
        catch (UnauthorizedAccessException)
        {
            return CatalogReadResult.Failure(CatalogStoreError.AccessDenied);
        }
        catch (IOException)
        {
            return CatalogReadResult.Failure(CatalogStoreError.IoFailure);
        }
    }

    public static CatalogWriteResult Write(CatalogSnapshot snapshot, string catalogPath)
    {
        ArgumentNullException.ThrowIfNull(snapshot);

        if (string.IsNullOrWhiteSpace(catalogPath) || !Path.IsPathFullyQualified(catalogPath))
        {
            return CatalogWriteResult.Failure(CatalogStoreError.InvalidPath);
        }
        if (snapshot.CatalogVersion != CatalogSnapshot.CurrentCatalogVersion ||
            snapshot.MinimumReaderVersion != CatalogSnapshot.OldestReaderVersion)
        {
            return CatalogWriteResult.Failure(CatalogStoreError.UnsupportedCatalogVersion);
        }

        Dictionary<CatalogEntityTable, List<DesiredRow>> desired = [];
        foreach (CatalogEntityTable table in CatalogEntityTables.All)
        {
            if (!TryProject(snapshot.Rows(table), out List<DesiredRow>? projected))
            {
                return CatalogWriteResult.Failure(CatalogStoreError.InvalidSnapshot);
            }
            desired[table] = projected;
        }

        try
        {
            string? parent = Path.GetDirectoryName(catalogPath);
            if (parent is not null)
            {
                Directory.CreateDirectory(parent);
            }
            if (StoragePathPolicy.IsExistingReparsePoint(catalogPath))
            {
                return CatalogWriteResult.Failure(CatalogStoreError.InvalidPath);
            }

            bool existed = File.Exists(catalogPath);
            using SqliteConnection connection = OpenConnection(
                catalogPath,
                SqliteOpenMode.ReadWriteCreate);

            Execute(connection, "PRAGMA journal_mode=DELETE");
            Execute(connection, "PRAGMA synchronous=FULL");
            Execute(connection, "PRAGMA foreign_keys=ON");

            long storageVersion = ScalarInt64(connection, "PRAGMA user_version");
            if (existed)
            {
                if (storageVersion != StorageSchemaVersion)
                {
                    return CatalogWriteResult.Failure(
                        CatalogStoreError.UnsupportedStorageVersion);
                }
                CreateTables(connection);
            }
            else
            {
                // 방금 만든 파일인데 user_version 이 0 이 아니면 우리가 만든 파일이 아닙니다.
                if (storageVersion != 0)
                {
                    return CatalogWriteResult.Failure(
                        CatalogStoreError.UnsupportedStorageVersion);
                }
                CreateTables(connection);
                Execute(connection, $"PRAGMA user_version={StorageSchemaVersion}");
            }

            Execute(connection, "BEGIN IMMEDIATE");
            try
            {
                UpsertMetadata(connection, snapshot);
                foreach (CatalogEntityTable table in CatalogEntityTables.All)
                {
                    SynchronizeRows(connection, table, desired[table]);
                }
                Execute(connection, "COMMIT");
            }
            catch
            {
                TryRollback(connection);
                throw;
            }

            // commit 뒤 readback 입니다. 여기서 실패하면 성공으로 보고하지 않습니다.
            if (!IsIntegral(connection))
            {
                return CatalogWriteResult.Failure(CatalogStoreError.CorruptDatabase);
            }
            return CatalogWriteResult.Success();
        }
        catch (SqliteException error)
        {
            return CatalogWriteResult.Failure(ClassifySqlite(error));
        }
        catch (UnauthorizedAccessException)
        {
            return CatalogWriteResult.Failure(CatalogStoreError.AccessDenied);
        }
        catch (IOException)
        {
            return CatalogWriteResult.Failure(CatalogStoreError.IoFailure);
        }
    }

    internal static bool IsValidRecoverySource(string catalogPath)
    {
        if (string.IsNullOrWhiteSpace(catalogPath) ||
            !Path.IsPathFullyQualified(catalogPath) ||
            !File.Exists(catalogPath) ||
            StoragePathPolicy.IsExistingReparsePoint(catalogPath))
        {
            return false;
        }

        try
        {
            using SqliteConnection connection = OpenConnection(
                catalogPath,
                SqliteOpenMode.ReadOnly);
            return IsIntegral(connection) &&
                ScalarInt64(connection, "PRAGMA user_version") == StorageSchemaVersion &&
                TryReadMetadata(
                    connection,
                    out int catalogVersion,
                    out int minimumReaderVersion,
                    out _) &&
                catalogVersion == CatalogSnapshot.CurrentCatalogVersion &&
                minimumReaderVersion == CatalogSnapshot.OldestReaderVersion;
        }
        catch (Exception error) when (error is SqliteException or IOException or
            UnauthorizedAccessException)
        {
            return false;
        }
    }

    private readonly record struct DesiredRow(string Id, long Position, byte[] Payload);

    private static SqliteConnection OpenConnection(string catalogPath, SqliteOpenMode mode)
    {
        // Pooling 은 반드시 꺼 둡니다. 6.0 부터 native 연결이 기본으로 pool 되어 Close 뒤에도
        // 파일 핸들이 남고, 그러면 backup 교체와 pending restore 의 파일 치환이 실패합니다.
        SqliteConnectionStringBuilder builder = new()
        {
            DataSource = catalogPath,
            Mode = mode,
            Cache = SqliteCacheMode.Private,
            Pooling = false,
            ForeignKeys = true,
            DefaultTimeout = 5,
        };
        SqliteConnection connection = new(builder.ConnectionString);
        connection.Open();
        return connection;
    }

    private static void Execute(SqliteConnection connection, string sql)
    {
        using SqliteCommand command = connection.CreateCommand();
        command.CommandText = sql;
        command.ExecuteNonQuery();
    }

    private static void TryRollback(SqliteConnection connection)
    {
        try
        {
            Execute(connection, "ROLLBACK");
        }
        catch (SqliteException)
        {
            // transaction 이 이미 끝났으면 되돌릴 것이 없습니다. 원래 실패를 덮지 않습니다.
        }
    }

    private static long ScalarInt64(SqliteConnection connection, string sql)
    {
        using SqliteCommand command = connection.CreateCommand();
        command.CommandText = sql;
        object? value = command.ExecuteScalar();
        return value is null or DBNull ? 0L : Convert.ToInt64(value, provider: null);
    }

    private static bool IsIntegral(SqliteConnection connection)
    {
        using SqliteCommand command = connection.CreateCommand();
        command.CommandText = "PRAGMA integrity_check";
        using SqliteDataReader reader = command.ExecuteReader();
        return reader.Read() &&
            !reader.IsDBNull(0) &&
            string.Equals(reader.GetString(0), "ok", StringComparison.Ordinal);
    }

    private static void CreateTables(SqliteConnection connection)
    {
        Execute(connection, """
            CREATE TABLE IF NOT EXISTS catalog_metadata (
              singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
              catalog_version INTEGER NOT NULL,
              minimum_reader_version INTEGER NOT NULL,
              active_roll_id TEXT
            )
            """);
        foreach (CatalogEntityTable table in CatalogEntityTables.All)
        {
            Execute(connection, $"""
                CREATE TABLE IF NOT EXISTS {CatalogEntityTables.SqlName(table)} (
                  id TEXT PRIMARY KEY NOT NULL,
                  position INTEGER NOT NULL UNIQUE CHECK (position >= 0),
                  payload BLOB NOT NULL
                )
                """);
        }
    }

    private static bool TryReadMetadata(
        SqliteConnection connection,
        out int catalogVersion,
        out int minimumReaderVersion,
        out string? activeRollId)
    {
        catalogVersion = 0;
        minimumReaderVersion = 0;
        activeRollId = null;

        using SqliteCommand command = connection.CreateCommand();
        command.CommandText = """
            SELECT catalog_version, minimum_reader_version, active_roll_id
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

    private static void UpsertMetadata(SqliteConnection connection, CatalogSnapshot snapshot)
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

    private static bool TryReadRows(
        SqliteConnection connection,
        CatalogEntityTable table,
        out IReadOnlyList<CatalogEntityRow> rows)
    {
        List<CatalogEntityRow> decoded = [];
        rows = decoded;

        using SqliteCommand command = connection.CreateCommand();
        command.CommandText =
            $"SELECT id, payload FROM {CatalogEntityTables.SqlName(table)} ORDER BY position ASC";
        using SqliteDataReader reader = command.ExecuteReader();
        while (reader.Read())
        {
            if (reader.IsDBNull(0) || reader.IsDBNull(1))
            {
                return false;
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
                return false;
            }
            if (node is not JsonObject payloadObject || id.Length == 0)
            {
                return false;
            }
            decoded.Add(new CatalogEntityRow(id, payloadObject));
        }
        return true;
    }

    private static bool TryProject(
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

    private static void SynchronizeRows(
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
            bump.Parameters.AddWithValue("$offset", PositionRelocationOffset);
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

    private static Dictionary<string, long> ReadPositions(
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

    private static CatalogStoreError ClassifySqlite(SqliteException error) =>
        error.SqliteErrorCode switch
        {
            SqliteBusy or SqliteLocked => CatalogStoreError.Busy,
            SqliteReadOnly => CatalogStoreError.AccessDenied,
            SqliteCantOpen => CatalogStoreError.IoFailure,
            _ => CatalogStoreError.CorruptDatabase,
        };
}
