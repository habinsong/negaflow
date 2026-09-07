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
            using SqliteConnection connection = SqliteCatalogSchema.OpenConnection(
                catalogPath,
                SqliteOpenMode.ReadOnly);
            if (!SqliteCatalogSchema.IsIntegral(connection))
            {
                return CatalogReadResult.Failure(CatalogStoreError.CorruptDatabase);
            }

            long storageVersion = SqliteCatalogSchema.ScalarInt64(connection, "PRAGMA user_version");
            if (storageVersion != StorageSchemaVersion)
            {
                return CatalogReadResult.Failure(
                    CatalogStoreError.UnsupportedStorageVersion,
                    (int)storageVersion);
            }

            if (!SqliteCatalogRows.TryReadMetadata(
                    connection,
                    out int catalogVersion,
                    out int minimumReaderVersion,
                    out string? activeRollId))
            {
                return CatalogReadResult.Failure(CatalogStoreError.MalformedContent);
            }
            // 예전 버전이 쓴 카탈로그는 사다리로 올려서 엽니다. 올릴 칸이 없거나 이 빌드보다
            // 높은 버전이면 그대로 물러납니다 - 모르는 형식을 추측해서 읽지 않습니다.
            bool needsPromotion = catalogVersion != CatalogSnapshot.CurrentCatalogVersion;
            if (!IsOpenableCatalogVersion(catalogVersion, minimumReaderVersion))
            {
                return CatalogReadResult.Failure(
                    CatalogStoreError.UnsupportedCatalogVersion,
                    catalogVersion);
            }

            Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>> tables = [];
            foreach (CatalogEntityTable table in CatalogEntityTables.All)
            {
                if (!SqliteCatalogRows.TryReadRows(connection, table, out IReadOnlyList<CatalogEntityRow>? rows))
                {
                    return CatalogReadResult.Failure(CatalogStoreError.MalformedContent);
                }
                tables[table] = rows;
            }

            CatalogSnapshot snapshot = new(
                catalogVersion,
                minimumReaderVersion,
                activeRollId,
                tables);
            if (needsPromotion)
            {
                if (!CatalogVersionMigration.TryPromote(
                        snapshot,
                        catalogVersion,
                        out CatalogSnapshot migrated))
                {
                    return CatalogReadResult.Failure(
                        CatalogStoreError.UnsupportedCatalogVersion,
                        catalogVersion);
                }
                snapshot = migrated;
            }
            return CatalogReadResult.Success(snapshot);
        }
        catch (SqliteException error)
        {
            return CatalogReadResult.Failure(SqliteCatalogSchema.ClassifySqlite(error));
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

    /// <summary>
    /// 이 빌드가 <b>열 수 있는</b> 논리 catalog version 인지입니다.
    /// </summary>
    /// <remarks>
    /// **읽기와 보존이 같은 규칙을 써야 하는 자리입니다.**
    ///
    /// 예전 판이 쓴 catalog 는 <see cref="Read"/> 가 승격 사다리로 올려서 엽니다. 그런데
    /// <see cref="IsValidRecoverySource"/> 는 디스크의 <b>원시</b> version 이 현재 상수와
    /// 정확히 같은지만 봤습니다. commit 은 새 primary 를 쓰기 <b>전에</b> 직전 primary 를
    /// 백업으로 보존하고, 그 보존이 이 검사를 통과해야 합니다. 그래서 catalog version 이 1
    /// 이던 사용자가 2 를 쓰는 빌드로 올라오면:
    ///
    /// - 읽기는 됩니다(사다리로 1 → 2). 사진도 다 보입니다.
    /// - 저장은 <b>전부</b> <see cref="CatalogStoreError.IoFailure"/> 로 막힙니다.
    /// - 보존이 먼저라 2 로 다시 쓸 기회가 영영 오지 않습니다. 교착입니다.
    /// - 종료 경로도 저장부터 하므로 <b>앱을 끌 수 없게 됩니다</b>.
    ///
    /// 실기에서 그대로 났습니다 — 130장 카탈로그가 catalogVersion=1 인 채로 열렸고,
    /// 종료할 때마다 `CatalogCommitFailed` 로 막혔습니다(termination.txt 12:57~12:58).
    /// 이 빌드가 읽어서 올릴 수 있는 catalog 는 보존 대상으로도 유효합니다.
    /// </remarks>
    internal static bool IsOpenableCatalogVersion(int catalogVersion, int minimumReaderVersion)
    {
        if (catalogVersion == CatalogSnapshot.CurrentCatalogVersion)
        {
            return minimumReaderVersion == CatalogSnapshot.OldestReaderVersion;
        }
        return catalogVersion < CatalogSnapshot.CurrentCatalogVersion &&
            minimumReaderVersion <= CatalogSnapshot.CurrentCatalogVersion &&
            CatalogVersionMigration.CanPromote(catalogVersion);
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

        Dictionary<CatalogEntityTable, List<SqliteCatalogRows.DesiredRow>> desired = [];
        foreach (CatalogEntityTable table in CatalogEntityTables.All)
        {
            if (!SqliteCatalogRows.TryProject(snapshot.Rows(table), out List<SqliteCatalogRows.DesiredRow>? projected))
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
            using SqliteConnection connection = SqliteCatalogSchema.OpenConnection(
                catalogPath,
                SqliteOpenMode.ReadWriteCreate);

            SqliteCatalogSchema.Execute(connection, "PRAGMA journal_mode=DELETE");
            SqliteCatalogSchema.Execute(connection, "PRAGMA synchronous=FULL");
            SqliteCatalogSchema.Execute(connection, "PRAGMA foreign_keys=ON");

            long storageVersion = SqliteCatalogSchema.ScalarInt64(connection, "PRAGMA user_version");
            if (existed)
            {
                if (storageVersion != StorageSchemaVersion)
                {
                    return CatalogWriteResult.Failure(
                        CatalogStoreError.UnsupportedStorageVersion);
                }
                SqliteCatalogSchema.CreateTables(connection);
            }
            else
            {
                // 방금 만든 파일인데 user_version 이 0 이 아니면 우리가 만든 파일이 아닙니다.
                if (storageVersion != 0)
                {
                    return CatalogWriteResult.Failure(
                        CatalogStoreError.UnsupportedStorageVersion);
                }
                SqliteCatalogSchema.CreateTables(connection);
                SqliteCatalogSchema.Execute(connection, $"PRAGMA user_version={StorageSchemaVersion}");
            }

            SqliteCatalogSchema.Execute(connection, "BEGIN IMMEDIATE");
            try
            {
                SqliteCatalogRows.UpsertMetadata(connection, snapshot);
                foreach (CatalogEntityTable table in CatalogEntityTables.All)
                {
                    SqliteCatalogRows.SynchronizeRows(connection, table, desired[table]);
                }
                SqliteCatalogSchema.Execute(connection, "COMMIT");
            }
            catch
            {
                SqliteCatalogSchema.TryRollback(connection);
                throw;
            }

            // commit 뒤 readback 입니다. 여기서 실패하면 성공으로 보고하지 않습니다.
            if (!SqliteCatalogSchema.IsIntegral(connection))
            {
                return CatalogWriteResult.Failure(CatalogStoreError.CorruptDatabase);
            }
            return CatalogWriteResult.Success();
        }
        catch (SqliteException error)
        {
            return CatalogWriteResult.Failure(SqliteCatalogSchema.ClassifySqlite(error));
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
            using SqliteConnection connection = SqliteCatalogSchema.OpenConnection(
                catalogPath,
                SqliteOpenMode.ReadOnly);
            return SqliteCatalogSchema.IsIntegral(connection) &&
                SqliteCatalogSchema.ScalarInt64(connection, "PRAGMA user_version") == StorageSchemaVersion &&
                SqliteCatalogRows.TryReadMetadata(
                    connection,
                    out int catalogVersion,
                    out int minimumReaderVersion,
                    out _) &&
                IsOpenableCatalogVersion(catalogVersion, minimumReaderVersion);
        }
        catch (Exception error) when (error is SqliteException or IOException or
            UnauthorizedAccessException)
        {
            return false;
        }
    }
}
