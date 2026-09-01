using static Negaflow.Catalog.UnitTests.CatalogTestAssert;
using static Negaflow.Catalog.UnitTests.CatalogStorageFixtures;

namespace Negaflow.Catalog.UnitTests;

/// <summary>
/// 저장 schema 는 앞으로도 자랍니다. 예전 빌드가 쓴 catalog 에는 나중에 붙은 컬럼이 없고,
/// 읽기는 READONLY 라 ALTER 로 붙일 수도 없습니다. 그 파일이 그대로 열리는지 재는 자리입니다.
/// macOS 대응: <c>LibraryCatalogSchemaCompatibilityTests.swift</c>.
/// </summary>
internal static class CatalogSchemaCompatibilityTests
{
    public static void Run(StorageRootSet roots)
    {
        VerifyCatalogWrittenBeforeAColumnWasAddedStillOpens(roots);
        VerifyWriteRestoresTheMissingColumn(roots);
        VerifySideRecordsAreReadLeniently(roots);
        VerifyFramesAreStillReadStrictly(roots);
    }

    /// <summary>
    /// 스캔 이력·컬렉션 같은 <b>부수 기록</b>은 한 줄이 낡은 형식이어도 그 줄만 버리고
    /// 엽니다 — 예전 버전이 쓴 payload 하나 때문에 사진 전체를 못 여는 일은 없어야 합니다.
    /// macOS 대응: <c>decodePayloads(_:lenient:)</c>.
    /// </summary>
    private static void VerifySideRecordsAreReadLeniently(StorageRootSet roots)
    {
        string catalogPath = Path.Combine(roots.LibraryRoot, "lenient-side-records.sqlite");
        Check(SqliteCatalogStore.Write(
                Snapshot("roll-a", Row("frame-1", "one"), Row("frame-2", "two")),
                catalogPath).IsSuccess,
            "lenient_side_fixture_write");

        // 못 읽는 payload 한 줄입니다. `{{` 는 JSON 이 아닙니다.
        ExecuteFixtureSql(
            catalogPath,
            "INSERT INTO manual_collections(id, position, payload) VALUES('bad', 0, X'7B7B')");
        // 같은 표에 멀쩡한 줄도 하나 둡니다 - 관대 처리가 표 전체를 버리면 안 됩니다.
        ExecuteFixtureSql(
            catalogPath,
            "INSERT INTO manual_collections(id, position, payload) VALUES('good', 1, X'7B7D')");

        CatalogReadResult read = SqliteCatalogStore.Read(catalogPath);
        Check(read.IsSuccess, "lenient_side_record_still_opens", () => read.Error.ToString());
        Check(FrameOrder(read) == "frame-1,frame-2", "lenient_side_record_keeps_frames");
        IReadOnlyList<CatalogEntityRow> collections =
            read.Snapshot?.Rows(CatalogEntityTable.ManualCollections) ?? [];
        Check(collections.Count == 1, "lenient_side_record_drops_only_the_bad_row",
            () => $"rows={collections.Count}");
        Check(collections.Count == 1 && collections[0].Id == "good",
            "lenient_side_record_keeps_the_good_row");
    }

    /// <summary>
    /// 사진·롤·폴더는 라이브러리의 뼈대라 한 줄이라도 못 읽으면 열지 않습니다.
    /// <b>관대 처리가 사진까지 번지지 않았음을 이 시험이 지킵니다.</b>
    /// </summary>
    private static void VerifyFramesAreStillReadStrictly(StorageRootSet roots)
    {
        foreach ((CatalogEntityTable table, string name) in
            (( CatalogEntityTable, string )[])
            [
                (CatalogEntityTable.Frames, "frames"),
                (CatalogEntityTable.Rolls, "rolls"),
                (CatalogEntityTable.Folders, "folders"),
            ])
        {
            string catalogPath = Path.Combine(roots.LibraryRoot, $"strict-{name}.sqlite");
            Check(SqliteCatalogStore.Write(
                    Snapshot("roll-a", Row("frame-1", "one")),
                    catalogPath).IsSuccess,
                $"strict_{name}_fixture_write");
            ExecuteFixtureSql(
                catalogPath,
                $"INSERT INTO {name}(id, position, payload) VALUES('bad', 900, X'7B7B')");

            CatalogReadResult read = SqliteCatalogStore.Read(catalogPath);
            Check(!read.IsSuccess, $"strict_{name}_refuses_to_open",
                () => read.Error.ToString());
            Check(read.Error == CatalogStoreError.MalformedContent,
                $"strict_{name}_reports_malformed",
                () => read.Error.ToString());
            Check(read.Snapshot is null, $"strict_{name}_no_partial_snapshot");
            Check(CatalogEntityTables.IsStrict(table), $"strict_{name}_is_declared_strict");
        }
    }

    /// <summary>
    /// 나중에 붙는 컬럼이 없는 예전 파일을 만들어 읽습니다. 지금 트리에서 선택 컬럼은
    /// <c>active_roll_id</c> 하나뿐이므로 그것을 떼어 예전 형태를 흉내 냅니다.
    /// </summary>
    private static void VerifyCatalogWrittenBeforeAColumnWasAddedStillOpens(StorageRootSet roots)
    {
        string catalogPath = Path.Combine(roots.LibraryRoot, "schema-compat-read.sqlite");
        CatalogSnapshot written = Snapshot(
            "roll-a",
            Row("frame-1", "one"),
            Row("frame-2", "two"));
        Check(SqliteCatalogStore.Write(written, catalogPath).IsSuccess,
            "schema_compat_fixture_write");

        ExecuteFixtureSql(catalogPath, "ALTER TABLE catalog_metadata DROP COLUMN active_roll_id");

        CatalogReadResult reopened = SqliteCatalogStore.Read(catalogPath);
        Check(reopened.IsSuccess, "schema_compat_missing_column_still_opens",
            () => $"error={reopened.Error}");
        Check(FrameOrder(reopened) == "frame-1,frame-2",
            "schema_compat_missing_column_keeps_frames",
            () => FrameOrder(reopened));
        Check(reopened.Snapshot?.ActiveRollId is null,
            "schema_compat_missing_column_reads_as_null");
        Check(CatalogRecovery.IsValidCatalogSource(catalogPath),
            "schema_compat_missing_column_is_recovery_source");
    }

    /// <summary>
    /// 쓰기는 ReadWrite 로 열리므로 빠진 컬럼을 그때 붙여야 합니다. 그러지 않으면 예전 파일은
    /// 영영 예전 형태로 남고, 다음 저장이 그 컬럼을 쓰는 순간 실패합니다.
    /// </summary>
    private static void VerifyWriteRestoresTheMissingColumn(StorageRootSet roots)
    {
        string catalogPath = Path.Combine(roots.LibraryRoot, "schema-compat-write.sqlite");
        Check(SqliteCatalogStore.Write(Snapshot("roll-a", Row("frame-1", "one")), catalogPath)
            .IsSuccess, "schema_compat_write_fixture_write");

        ExecuteFixtureSql(catalogPath, "ALTER TABLE catalog_metadata DROP COLUMN active_roll_id");

        CatalogWriteResult rewritten = SqliteCatalogStore.Write(
            Snapshot("roll-b", Row("frame-1", "one"), Row("frame-2", "two")),
            catalogPath);
        Check(rewritten.IsSuccess, "schema_compat_write_over_old_shape",
            () => $"error={rewritten.Error}");

        CatalogReadResult reopened = SqliteCatalogStore.Read(catalogPath);
        Check(reopened.Snapshot?.ActiveRollId == "roll-b",
            "schema_compat_write_restores_active_roll",
            () => reopened.Snapshot?.ActiveRollId ?? "<null>");
        Check(FrameOrder(reopened) == "frame-1,frame-2",
            "schema_compat_write_keeps_frames");
    }
}
