using Microsoft.Data.Sqlite;

namespace Negaflow.Catalog;

/// <summary>
/// 열지 못한 카탈로그가 <b>어떻게</b> 어긋났는지입니다. 실패 코드 하나로는
/// <c>CorruptDatabase</c> 까지밖에 알 수 없어, 지원 요청을 받았을 때 원인을 좁힐 유일한
/// 단서입니다. macOS <c>LibraryRecoveryCatalogInspection</c> 자리입니다.
/// </summary>
/// <remarks>경로·파일명·사진 내용은 담지 않습니다. 코드와 개수만 담습니다.</remarks>
public sealed record CatalogFileInspection(
    CatalogStoreError Readability,
    int? CatalogVersion,
    long? StorageVersion,
    IReadOnlyList<CatalogTableRowCount> TableRows,
    bool IntegrityCheckPassed);

/// <summary>표 하나의 행 수입니다. 표 이름은 우리가 만든 상수입니다.</summary>
public readonly record struct CatalogTableRowCount(string Table, long Rows);

/// <summary>
/// 열지 못한 카탈로그 파일을 READONLY 로 다시 열어 관측한 사실만 적습니다. 아무 것도
/// 고치지 않고, 잠금도 잡지 않습니다.
/// </summary>
public static class CatalogFileInspector
{
    public static CatalogFileInspection Inspect(string catalogPath)
    {
        if (string.IsNullOrWhiteSpace(catalogPath) || !Path.IsPathFullyQualified(catalogPath))
        {
            return new CatalogFileInspection(
                CatalogStoreError.InvalidPath,
                null,
                null,
                [],
                IntegrityCheckPassed: false);
        }
        if (!File.Exists(catalogPath))
        {
            return new CatalogFileInspection(
                CatalogStoreError.NotFound,
                null,
                null,
                [],
                IntegrityCheckPassed: false);
        }

        try
        {
            using SqliteConnection connection = SqliteCatalogSchema.OpenConnection(
                catalogPath,
                SqliteOpenMode.ReadOnly);
            bool integral = SqliteCatalogSchema.IsIntegral(connection);
            long storageVersion = SqliteCatalogSchema.ScalarInt64(
                connection,
                "PRAGMA user_version");
            int? catalogVersion = null;
            if (SqliteCatalogRows.TryReadMetadata(
                    connection,
                    out int observed,
                    out _,
                    out _))
            {
                catalogVersion = observed;
            }

            List<CatalogTableRowCount> rowCounts = [];
            foreach (CatalogEntityTable table in CatalogEntityTables.All)
            {
                string name = CatalogEntityTables.SqlName(table);
                try
                {
                    rowCounts.Add(new CatalogTableRowCount(
                        name,
                        SqliteCatalogSchema.ScalarInt64(connection, $"SELECT COUNT(*) FROM {name}")));
                }
                catch (SqliteException)
                {
                    // 표가 없거나 못 읽으면 -1 로 남깁니다 - 0 으로 적으면 "비어 있었다" 로
                    // 읽혀 다음 사람이 엉뚱한 곳을 봅니다.
                    rowCounts.Add(new CatalogTableRowCount(name, -1));
                }
            }

            return new CatalogFileInspection(
                SqliteCatalogStore.Read(catalogPath).Error,
                catalogVersion,
                storageVersion,
                rowCounts,
                integral);
        }
        catch (SqliteException error)
        {
            return new CatalogFileInspection(
                SqliteCatalogSchema.ClassifySqlite(error),
                null,
                null,
                [],
                IntegrityCheckPassed: false);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            return new CatalogFileInspection(
                error is UnauthorizedAccessException
                    ? CatalogStoreError.AccessDenied
                    : CatalogStoreError.IoFailure,
                null,
                null,
                [],
                IntegrityCheckPassed: false);
        }
    }
}
