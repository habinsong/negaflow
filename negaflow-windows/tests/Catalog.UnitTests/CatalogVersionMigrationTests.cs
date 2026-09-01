using static Negaflow.Catalog.UnitTests.CatalogTestAssert;
using static Negaflow.Catalog.UnitTests.CatalogStorageFixtures;

namespace Negaflow.Catalog.UnitTests;

/// <summary>
/// 논리 catalog version 을 올리는 자리와, 복구 과정에서 옆에 둔 사본을 정리하는 자리를
/// 재는 곳입니다. 둘 다 <b>예방</b>입니다 — 지금 사용자에게는 문제가 없지만, 없으면
/// 그날 전체 사용자를 잃습니다.
/// </summary>
internal static class CatalogVersionMigrationTests
{
    public static void Run(StorageRootSet roots)
    {
        VerifyLowerVersionIsPromoted(roots);
        VerifyFutureVersionIsStillRefused(roots);
        VerifySidelinedCopiesArePruned(roots);
    }

    /// <summary>
    /// 이 빌드보다 낮은 버전은 사다리로 올려서 엽니다. 지금 사다리는 비어 있으므로
    /// <b>시험 이음매</b>로 칸 하나를 넣어 그 경로 자체를 지납니다.
    /// </summary>
    private static void VerifyLowerVersionIsPromoted(StorageRootSet roots)
    {
        string catalogPath = Path.Combine(roots.LibraryRoot, "migration-promote.sqlite");
        Check(SqliteCatalogStore.Write(
                Snapshot("roll-a", Row("frame-1", "one"), Row("frame-2", "two")),
                catalogPath).IsSuccess,
            "migration_fixture_write");

        // 예전 빌드가 쓴 것처럼 논리 version 을 0 으로 내립니다.
        SetCatalogVersion(catalogPath, 0);
        CatalogReadResult withoutLadder = SqliteCatalogStore.Read(catalogPath);
        Check(withoutLadder.Error == CatalogStoreError.UnsupportedCatalogVersion,
            "migration_without_ladder_refuses",
            () => withoutLadder.Error.ToString());
        Check(withoutLadder.ObservedVersion == 0, "migration_without_ladder_reports_version");

        int promoted = 0;
        CatalogVersionMigration.LadderForTesting =
            new Dictionary<int, (int To, CatalogVersionMigration.Promotion Promote)>
            {
                [0] = (CatalogSnapshot.CurrentCatalogVersion, source =>
                {
                    promoted++;
                    Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>> tables = [];
                    foreach (CatalogEntityTable table in CatalogEntityTables.All)
                    {
                        tables[table] = source.Rows(table);
                    }
                    return new CatalogSnapshot(source.ActiveRollId, tables);
                }),
            };
        try
        {
            CatalogReadResult migrated = SqliteCatalogStore.Read(catalogPath);
            Check(migrated.IsSuccess, "migration_promotes_lower_version",
                () => migrated.Error.ToString());
            Check(promoted == 1, "migration_runs_each_step_once", () => $"steps={promoted}");
            Check(migrated.Snapshot?.CatalogVersion == CatalogSnapshot.CurrentCatalogVersion,
                "migration_reports_current_version");
            // 사진은 한 장도 잃지 않아야 합니다.
            Check(FrameOrder(migrated) == "frame-1,frame-2", "migration_keeps_frames");
            Check(migrated.Snapshot?.ActiveRollId == "roll-a", "migration_keeps_active_roll");
        }
        finally
        {
            CatalogVersionMigration.LadderForTesting = null;
        }

        // 이음매를 걷으면 다시 물러납니다 - 시험이 제품 동작을 바꾸지 않았음을 확인합니다.
        Check(SqliteCatalogStore.Read(catalogPath).Error ==
            CatalogStoreError.UnsupportedCatalogVersion,
            "migration_seam_does_not_leak");
    }

    /// <summary>
    /// 이 빌드보다 <b>높은</b> 버전은 승격 대상이 아닙니다. macOS 파일(6)이 그 예이며,
    /// 추측해서 읽으면 사용자의 카탈로그를 망칩니다.
    /// </summary>
    private static void VerifyFutureVersionIsStillRefused(StorageRootSet roots)
    {
        string catalogPath = Path.Combine(roots.LibraryRoot, "migration-future.sqlite");
        Check(SqliteCatalogStore.Write(Snapshot(null, Row("frame-1", "one")), catalogPath)
            .IsSuccess, "migration_future_fixture_write");
        SetCatalogVersion(catalogPath, 6);

        CatalogVersionMigration.LadderForTesting =
            new Dictionary<int, (int To, CatalogVersionMigration.Promotion Promote)>
            {
                [6] = (CatalogSnapshot.CurrentCatalogVersion, _ => CatalogSnapshot.Empty),
            };
        try
        {
            CatalogReadResult read = SqliteCatalogStore.Read(catalogPath);
            Check(read.Error == CatalogStoreError.UnsupportedCatalogVersion,
                "migration_future_still_refused",
                () => read.Error.ToString());
            Check(read.ObservedVersion == 6, "migration_future_reports_version");
        }
        finally
        {
            CatalogVersionMigration.LadderForTesting = null;
        }
    }

    /// <summary>
    /// 옆에 둔 사본은 마지막으로 기댈 것이라 무조건 지우면 안 되고, 무한정 쌓아 두면 지원
    /// 폴더가 계속 커집니다 — macOS 는 이 정리를 안 해서 9.2MB 가 쌓여 있었습니다.
    /// </summary>
    private static void VerifySidelinedCopiesArePruned(StorageRootSet parentRoots)
    {
        string base_ = Path.Combine(parentRoots.LocalApplicationDataRoot, "sidelined");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(base_).Roots!;
        Check(SqliteCatalogStore.Write(
                Snapshot("roll-a", Row("frame-1", "one")),
                roots.CatalogPath).IsSuccess,
            "sidelined_fixture_write");
        Directory.CreateDirectory(roots.DefectRecipeRoot);

        for (int attempt = 0; attempt < 5; attempt++)
        {
            Check(CatalogSidelinedFiles.Preserve(roots), $"sidelined_preserve_{attempt}");
        }

        string[] copies = Directory.GetFiles(roots.LibraryRoot, "library.corrupt-*");
        Check(copies.Length == CatalogSidelinedFiles.DefaultRetentionCount,
            "sidelined_keeps_only_the_retention_count",
            () => $"copies={copies.Length}");
        // 원본은 그대로 있어야 합니다 - 보관은 복사이지 이동이 아닙니다.
        Check(File.Exists(roots.CatalogPath), "sidelined_leaves_the_original");
        Check(SqliteCatalogStore.Read(roots.CatalogPath).IsSuccess,
            "sidelined_original_still_reads");
        // 남긴 사본은 진짜 카탈로그여야 합니다 - 껍데기를 남기면 기댈 것이 없습니다.
        Check(copies.All(path => SqliteCatalogStore.Read(path).IsSuccess),
            "sidelined_copies_are_readable_catalogs");

        string[] defectCopies = Directory.GetDirectories(roots.LibraryRoot, "defects.corrupt-*");
        Check(defectCopies.Length == CatalogSidelinedFiles.DefaultRetentionCount,
            "sidelined_prunes_defect_folders_too",
            () => $"folders={defectCopies.Length}");
    }
}
