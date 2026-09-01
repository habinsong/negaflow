using Microsoft.Data.Sqlite;

namespace Negaflow.Catalog;

/// <summary>
/// SQLite 연결을 여는 규율과 물리 schema 입니다. 어떤 row 를 담을지는
/// <see cref="SqliteCatalogRows"/>, 어떤 순서로 읽고 쓸지는 <see cref="SqliteCatalogStore"/>.
/// </summary>
internal static class SqliteCatalogSchema
{
    internal const long PositionRelocationOffset = 1L << 40;

    internal const int SqliteBusy = 5;
    internal const int SqliteLocked = 6;
    internal const int SqliteReadOnly = 8;
    internal const int SqliteIoError = 10;
    internal const int SqliteFull = 13;
    internal const int SqliteCantOpen = 14;

    internal static SqliteConnection OpenConnection(string catalogPath, SqliteOpenMode mode)
    {
        // Pooling 은 반드시 꺼 둡니다. 6.0 부터 native 연결이 기본으로 pool 되어 Close 뒤에도
        // 파일 핸들이 남고, 그러면 backup 교체와 pending restore 의 파일 치환이 실패합니다.
        SqliteConnectionStringBuilder builder = new()
        {
            // SQLite native 도 확장 경로 접두사 없이는 MAX_PATH(260) 를 넘는 경로를 못 엽니다.
            // 260자 catalog 에서 promotion 검증(IsValidRecoverySource)이 여기서 실패했습니다.
            DataSource = StorageExtendedPath.ToExtendedPath(catalogPath),
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

    internal static void Execute(SqliteConnection connection, string sql)
    {
        using SqliteCommand command = connection.CreateCommand();
        command.CommandText = sql;
        command.ExecuteNonQuery();
    }

    internal static void TryRollback(SqliteConnection connection)
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

    internal static long ScalarInt64(SqliteConnection connection, string sql)
    {
        using SqliteCommand command = connection.CreateCommand();
        command.CommandText = sql;
        object? value = command.ExecuteScalar();
        return value is null or DBNull ? 0L : Convert.ToInt64(value, provider: null);
    }

    internal static bool IsIntegral(SqliteConnection connection)
    {
        using SqliteCommand command = connection.CreateCommand();
        command.CommandText = "PRAGMA integrity_check";
        using SqliteDataReader reader = command.ExecuteReader();
        return reader.Read() &&
            !reader.IsDBNull(0) &&
            string.Equals(reader.GetString(0), "ok", StringComparison.Ordinal);
    }

    internal const string MetadataTable = "catalog_metadata";

    /// <summary>
    /// <see cref="MetadataTable"/> 없이는 이 파일이 우리 것인지조차 판정할 수 없는 컬럼입니다.
    /// 하나라도 없으면 <see cref="CatalogStoreError.MalformedContent"/> 로 물러납니다.
    /// </summary>
    internal static readonly string[] RequiredMetadataColumns =
        ["singleton", "catalog_version", "minimum_reader_version"];

    /// <summary>
    /// <see cref="MetadataTable"/> 에서 <b>없을 수 있는</b> 컬럼입니다. 예전 빌드가 쓴 파일에는
    /// 나중에 붙은 컬럼이 없고, 읽기는 READONLY 라 그때 ALTER 로 붙일 수 없습니다.
    /// <para>
    /// <b>앞으로 컬럼을 추가할 때의 규율입니다.</b> 새 metadata 컬럼은 반드시 NULL 을 허용하는
    /// 선택 컬럼으로 만들어 여기에 올리십시오. 읽기 경로는 그 컬럼이 <b>없을 수 있다고 가정</b>
    /// 하고, 쓰기 경로가 <see cref="CreateTables"/> 에서 뒤늦게 붙입니다. 이 규율을 어기고
    /// 필수 컬럼을 추가하면, 그 순간 기존 사용자 전원이 라이브러리를 열지 못합니다.
    /// </para>
    /// </summary>
    internal static readonly (string Name, string Declaration)[] OptionalMetadataColumns =
        [("active_roll_id", "TEXT")];

    internal static void CreateTables(SqliteConnection connection)
    {
        Execute(connection, $"""
            CREATE TABLE IF NOT EXISTS {MetadataTable} (
              singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
              catalog_version INTEGER NOT NULL,
              minimum_reader_version INTEGER NOT NULL,
              active_roll_id TEXT
            )
            """);
        // 예전 형태로 남은 파일에 빠진 선택 컬럼을 여기서 붙입니다. 쓰기 연결에서만 할 수 있고,
        // 이것을 하지 않으면 예전 파일은 영영 예전 형태로 남습니다.
        HashSet<string> metadataColumns = TableColumns(connection, MetadataTable);
        foreach ((string name, string declaration) in OptionalMetadataColumns)
        {
            if (!metadataColumns.Contains(name))
            {
                Execute(connection, $"ALTER TABLE {MetadataTable} ADD COLUMN {name} {declaration}");
            }
        }
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


    /// <summary>
    /// 표에 실제로 있는 컬럼 이름입니다. READONLY 연결에서도 물을 수 있습니다.
    /// </summary>
    internal static HashSet<string> TableColumns(SqliteConnection connection, string table)
    {
        HashSet<string> columns = new(StringComparer.Ordinal);
        using SqliteCommand command = connection.CreateCommand();
        command.CommandText = $"PRAGMA table_info({table})";
        using SqliteDataReader reader = command.ExecuteReader();
        while (reader.Read())
        {
            if (!reader.IsDBNull(1))
            {
                columns.Add(reader.GetString(1));
            }
        }
        return columns;
    }

    internal static CatalogStoreError ClassifySqlite(SqliteException error) =>
        error.SqliteErrorCode switch
        {
            SqliteBusy or SqliteLocked => CatalogStoreError.Busy,
            SqliteReadOnly => CatalogStoreError.AccessDenied,
            SqliteIoError or SqliteFull or SqliteCantOpen => CatalogStoreError.IoFailure,
            _ => CatalogStoreError.CorruptDatabase,
        };
}
