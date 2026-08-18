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

    internal static void CreateTables(SqliteConnection connection)
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


    internal static CatalogStoreError ClassifySqlite(SqliteException error) =>
        error.SqliteErrorCode switch
        {
            SqliteBusy or SqliteLocked => CatalogStoreError.Busy,
            SqliteReadOnly => CatalogStoreError.AccessDenied,
            SqliteIoError or SqliteFull or SqliteCantOpen => CatalogStoreError.IoFailure,
            _ => CatalogStoreError.CorruptDatabase,
        };
}
