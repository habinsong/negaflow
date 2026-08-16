using System.Diagnostics;
using System.IO.Compression;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.Data.Sqlite;
using static Negaflow.Catalog.UnitTests.CatalogTestAssert;
using static Negaflow.Catalog.UnitTests.CatalogStorageFixtures;

namespace Negaflow.Catalog.UnitTests;

internal static class SqliteCatalogStoreTests
{
    public static void Run(StorageRootSet roots)
    {
        VerifyStoreLifecycle(roots);
        VerifyStoreRefusals(roots);
        VerifyVerifiedCommit(roots);
    }

    private static void VerifyStoreLifecycle(StorageRootSet roots)
    {
        string catalogPath = roots.CatalogPath;

        // 없는 파일을 빈 라이브러리로 읽지 않습니다.
        CatalogReadResult absent = SqliteCatalogStore.Read(catalogPath);
        Check(!absent.IsSuccess, "store_absent_not_success");
        Check(absent.Error == CatalogStoreError.NotFound, "store_absent_not_found");
        Check(absent.Snapshot is null, "store_absent_no_partial_snapshot");

        CatalogSnapshot first = Snapshot(
            "roll-a",
            Row("frame-1", "one"),
            Row("frame-2", "two"),
            Row("frame-3", "three"));
        Check(SqliteCatalogStore.Write(first, catalogPath).IsSuccess, "store_first_write");
        Check(File.Exists(catalogPath), "store_first_write_creates_file");

        CatalogReadResult reopened = SqliteCatalogStore.Read(catalogPath);
        Check(reopened.IsSuccess, "store_reopen_success");
        Check(FrameOrder(reopened) == "frame-1,frame-2,frame-3", "store_reopen_preserves_order");
        Check(FrameLabels(reopened) == "one,two,three", "store_reopen_preserves_payload");
        Check(reopened.Snapshot?.ActiveRollId == "roll-a", "store_reopen_preserves_active_roll");
        Check(reopened.Snapshot?.Rows(CatalogEntityTable.Rolls).Count == 0,
            "store_reopen_untouched_table_empty");

        // 자리 바꾸기입니다. position 이 UNIQUE 이므로 재배치 중 제약을 어기면 여기서 걸립니다.
        CatalogSnapshot reordered = Snapshot(
            "roll-a",
            Row("frame-3", "three"),
            Row("frame-1", "one-edited"),
            Row("frame-2", "two"));
        Check(SqliteCatalogStore.Write(reordered, catalogPath).IsSuccess, "store_reorder_write");
        CatalogReadResult afterReorder = SqliteCatalogStore.Read(catalogPath);
        Check(FrameOrder(afterReorder) == "frame-3,frame-1,frame-2", "store_reorder_order");
        Check(FrameLabels(afterReorder) == "three,one-edited,two", "store_reorder_payload");

        // 되돌리기도 같은 경로를 반대 방향으로 지납니다.
        Check(SqliteCatalogStore.Write(first, catalogPath).IsSuccess, "store_reorder_back_write");
        Check(FrameOrder(SqliteCatalogStore.Read(catalogPath)) == "frame-1,frame-2,frame-3",
            "store_reorder_back_order");

        CatalogSnapshot removed = Snapshot("roll-a", Row("frame-2", "two"));
        Check(SqliteCatalogStore.Write(removed, catalogPath).IsSuccess, "store_remove_write");
        CatalogReadResult afterRemove = SqliteCatalogStore.Read(catalogPath);
        Check(FrameOrder(afterRemove) == "frame-2", "store_remove_drops_rows");

        CatalogSnapshot cleared = Snapshot(activeRollId: null);
        Check(SqliteCatalogStore.Write(cleared, catalogPath).IsSuccess, "store_clear_write");
        CatalogReadResult afterClear = SqliteCatalogStore.Read(catalogPath);
        Check(afterClear.IsSuccess, "store_clear_reopen_success");
        Check(afterClear.Snapshot?.Rows(CatalogEntityTable.Frames).Count == 0,
            "store_clear_empties_table");
        Check(afterClear.Snapshot?.ActiveRollId is null, "store_clear_active_roll_null");

        Check(CatalogRecovery.IsValidCatalogSource(catalogPath),
            "store_valid_recovery_source");

        // Pooling 을 켜 두면 여기서 파일이 잠겨 backup 교체가 막힙니다.
        File.Delete(catalogPath);
        Check(!File.Exists(catalogPath), "store_no_lingering_file_handle");
    }

    private static void VerifyStoreRefusals(StorageRootSet roots)
    {
        string catalogPath = Path.Combine(roots.LibraryRoot, "refusals.sqlite");

        CatalogSnapshot duplicated = Snapshot(
            null,
            Row("frame-1", "one"),
            Row("frame-1", "again"));
        CatalogWriteResult duplicateWrite = SqliteCatalogStore.Write(duplicated, catalogPath);
        Check(duplicateWrite.Error == CatalogStoreError.InvalidSnapshot,
            "store_rejects_duplicate_ids");
        Check(!File.Exists(catalogPath), "store_rejects_duplicate_ids_without_creating_file");

        CatalogSnapshot emptyId = Snapshot(null, Row(string.Empty, "one"));
        Check(SqliteCatalogStore.Write(emptyId, catalogPath).Error ==
            CatalogStoreError.InvalidSnapshot, "store_rejects_empty_id");

        Check(SqliteCatalogStore.Write(Snapshot(null, Row("frame-1", "one")), catalogPath)
            .IsSuccess, "store_refusal_fixture_write");

        // 물리 schema 가 미래 버전이면 읽지 않습니다.
        SetStorageVersion(catalogPath, 99);
        CatalogReadResult futureStorage = SqliteCatalogStore.Read(catalogPath);
        Check(futureStorage.Error == CatalogStoreError.UnsupportedStorageVersion,
            "store_rejects_future_storage_version");
        Check(futureStorage.ObservedVersion == 99, "store_reports_observed_storage_version");
        Check(!CatalogRecovery.IsValidCatalogSource(catalogPath),
            "store_future_storage_is_not_recovery_source");
        Check(SqliteCatalogStore.Write(Snapshot(null), catalogPath).Error ==
            CatalogStoreError.UnsupportedStorageVersion,
            "store_refuses_write_over_future_storage_version");
        SetStorageVersion(catalogPath, 1);

        // macOS 파일은 논리 version 6 입니다. 조용히 읽지 않고 그 값을 보고합니다.
        SetCatalogVersion(catalogPath, 6);
        CatalogReadResult foreign = SqliteCatalogStore.Read(catalogPath);
        Check(foreign.Error == CatalogStoreError.UnsupportedCatalogVersion,
            "store_rejects_foreign_catalog_version");
        Check(foreign.ObservedVersion == 6, "store_reports_observed_catalog_version");
        Check(!CatalogRecovery.IsValidCatalogSource(catalogPath),
            "store_foreign_catalog_is_not_recovery_source");
        SetCatalogVersion(catalogPath, CatalogSnapshot.CurrentCatalogVersion);
        Check(SqliteCatalogStore.Read(catalogPath).IsSuccess, "store_restored_fixture_reads");

        string garbagePath = Path.Combine(roots.LibraryRoot, "garbage.sqlite");
        File.WriteAllBytes(garbagePath, "this is not a database"u8.ToArray());
        CatalogReadResult garbage = SqliteCatalogStore.Read(garbagePath);
        Check(garbage.Error == CatalogStoreError.CorruptDatabase, "store_rejects_garbage_file");
        Check(garbage.Snapshot is null, "store_garbage_no_partial_snapshot");
        Check(!CatalogRecovery.IsValidCatalogSource(garbagePath),
            "store_garbage_is_not_recovery_source");
        Check(SqliteCatalogStore.Write(Snapshot(null), garbagePath).Error !=
            CatalogStoreError.None, "store_refuses_write_over_garbage_file");

        Check(SqliteCatalogStore.Read("library.sqlite").Error == CatalogStoreError.InvalidPath,
            "store_rejects_relative_path");
        Check(SqliteCatalogStore.Write(Snapshot(null), "library.sqlite").Error ==
            CatalogStoreError.InvalidPath, "store_write_rejects_relative_path");
    }

    private static void VerifyVerifiedCommit(StorageRootSet parentRoots)
    {
        string commitBase = Path.Combine(parentRoots.LocalApplicationDataRoot, "verified-commit");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(commitBase).Roots!;
        CatalogSessionOpenResult opened = CatalogSession.Open(roots);
        using CatalogSession? session = opened.Session;
        Check(opened.IsSuccess, "commit_session_open");
        if (session is null)
        {
            return;
        }

        Check(session.ReadOrCreate().IsSuccess, "commit_initial_create");
        Check(!File.Exists(roots.CatalogBackupPath), "commit_initial_create_has_no_backup");

        CatalogSnapshot baseline = Snapshot("roll-a", Row("frame-1", "baseline"));
        CatalogSnapshot changed = Snapshot("roll-b", Row("frame-2", "changed"));
        CatalogSnapshot next = Snapshot("roll-c", Row("frame-3", "next"));
        Check(session.Write(baseline).IsSuccess, "commit_baseline_write");
        byte[] baselinePrimary = File.ReadAllBytes(roots.CatalogPath);
        Check(session.Write(changed).IsSuccess, "commit_changed_write");
        Check(File.Exists(roots.CatalogBackupPath), "commit_previous_primary_backup_exists");
        if (!File.Exists(roots.CatalogBackupPath))
        {
            return;
        }
        Check(File.ReadAllBytes(roots.CatalogBackupPath).SequenceEqual(baselinePrimary),
            "commit_previous_primary_backup_exact_bytes");
        Check(FrameLabels(SqliteCatalogStore.Read(roots.CatalogBackupPath)) == "baseline",
            "commit_previous_primary_backup_payload");

        byte[] backupBeforeNoOp = File.ReadAllBytes(roots.CatalogBackupPath);
        Check(session.Write(changed).IsSuccess, "commit_noop_success");
        Check(File.ReadAllBytes(roots.CatalogBackupPath).SequenceEqual(backupBeforeNoOp),
            "commit_noop_preserves_older_backup");

        byte[] changedPrimary = File.ReadAllBytes(roots.CatalogPath);
        CatalogWriteResult mismatch = CatalogCommitVerifier.CommitForTesting(
            next,
            roots,
            readback: _ => CatalogReadResult.Success(
                Snapshot("roll-wrong", Row("frame-wrong", "wrong"))));
        Check(mismatch.Error == CatalogStoreError.ReadbackFailed,
            "commit_readback_mismatch_error");
        Check(File.ReadAllBytes(roots.CatalogPath).SequenceEqual(changedPrimary),
            "commit_readback_mismatch_restores_exact_primary");
        Check(FrameLabels(session.Read()) == "changed",
            "commit_readback_mismatch_restores_payload");

        CatalogWriteResult writerFailure = CatalogCommitVerifier.CommitForTesting(
            next,
            roots,
            writer: (_, path) =>
            {
                CatalogWriteResult substituted = SqliteCatalogStore.Write(
                    Snapshot("roll-external", Row("frame-external", "external")),
                    roots.CatalogBackupPath);
                if (!substituted.IsSuccess)
                {
                    return substituted;
                }
                File.WriteAllBytes(path, "partial write"u8.ToArray());
                throw new IOException("injected writer failure");
            });
        Check(writerFailure.Error == CatalogStoreError.IoFailure,
            "commit_writer_failure_error");
        Check(File.ReadAllBytes(roots.CatalogPath).SequenceEqual(changedPrimary),
            "commit_writer_failure_restores_exact_primary");
        Check(FrameLabels(session.Read()) == "changed",
            "commit_writer_failure_restores_payload");

        CatalogWriteResult rollbackFailure = session.WriteForTesting(
            next,
            readback: _ => CatalogReadResult.Failure(CatalogStoreError.CorruptDatabase),
            restore: (_, _) => false);
        Check(rollbackFailure.Error == CatalogStoreError.RollbackFailed,
            "commit_rollback_failure_is_distinct");
        Check(FrameLabels(session.Read()) == "next",
            "commit_rollback_failure_does_not_claim_old_primary");
        byte[] unverifiedPrimary = File.ReadAllBytes(roots.CatalogPath);
        byte[] knownGoodBackup = File.ReadAllBytes(roots.CatalogBackupPath);
        Check(session.Write(baseline).Error == CatalogStoreError.RollbackFailed,
            "commit_rollback_failure_blocks_followup_write");
        Check(session.ReadOrCreate().Error == CatalogStoreError.RollbackFailed,
            "commit_rollback_failure_blocks_normal_open");
        Check(File.ReadAllBytes(roots.CatalogPath).SequenceEqual(unverifiedPrimary) &&
              File.ReadAllBytes(roots.CatalogBackupPath).SequenceEqual(knownGoodBackup),
            "commit_blocked_followup_preserves_primary_and_backup");

        string absenceBase = Path.Combine(
            parentRoots.LocalApplicationDataRoot,
            "verified-commit-absence");
        StorageRootSet absenceRoots = StorageRootResolver.ResolveForTests(absenceBase).Roots!;
        string journalPath = $"{absenceRoots.CatalogPath}-journal";
        CatalogWriteResult absenceMismatch = CatalogCommitVerifier.CommitForTesting(
            baseline,
            absenceRoots,
            writer: (_, path) =>
            {
                Directory.CreateDirectory(Path.GetDirectoryName(path)!);
                File.WriteAllBytes(path, "partial database"u8.ToArray());
                File.WriteAllBytes(journalPath, "hot journal"u8.ToArray());
                return CatalogWriteResult.Failure(CatalogStoreError.IoFailure);
            });
        Check(absenceMismatch.Error == CatalogStoreError.IoFailure,
            "commit_absence_writer_error");
        Check(!File.Exists(absenceRoots.CatalogPath),
            "commit_absence_writer_restores_absence");
        Check(!File.Exists(journalPath),
            "commit_absence_writer_removes_journal");
        Check(!File.Exists(absenceRoots.CatalogBackupPath),
            "commit_absence_readback_does_not_create_backup");

        string guardedBase = Path.Combine(
            parentRoots.LocalApplicationDataRoot,
            "verified-commit-guarded");
        StorageRootSet guardedRoots = StorageRootResolver.ResolveForTests(guardedBase).Roots!;
        CatalogSessionOpenResult guardedOpen = CatalogSession.Open(guardedRoots);
        using CatalogSession? guarded = guardedOpen.Session;
        Check(guardedOpen.IsSuccess, "commit_guarded_session_open");
        if (guarded is null)
        {
            return;
        }
        Check(guarded.ReadOrCreate().IsSuccess, "commit_guarded_create");
        Check(guarded.Write(baseline).IsSuccess, "commit_guarded_baseline");
        Check(guarded.Write(changed).IsSuccess, "commit_guarded_changed");
        byte[] guardedBackup = File.ReadAllBytes(guardedRoots.CatalogBackupPath);

        File.Delete(guardedRoots.CatalogPath);
        Check(guarded.ReadOrCreate().Error == CatalogStoreError.MissingAuthoritativeData,
            "commit_missing_primary_with_backup_blocks_empty_create");
        Check(!File.Exists(guardedRoots.CatalogPath),
            "commit_missing_primary_with_backup_preserves_absence");
        Check(File.ReadAllBytes(guardedRoots.CatalogBackupPath).SequenceEqual(guardedBackup),
            "commit_missing_primary_preserves_backup");

        File.Copy(guardedRoots.CatalogBackupPath, guardedRoots.CatalogPath);
        byte[] corruptPrimary = "not a database"u8.ToArray();
        File.WriteAllBytes(guardedRoots.CatalogPath, corruptPrimary);
        CatalogWriteResult corruptWrite = guarded.Write(next);
        Check(corruptWrite.Error == CatalogStoreError.CorruptDatabase,
            "commit_corrupt_primary_refuses_write");
        Check(File.ReadAllBytes(guardedRoots.CatalogPath).SequenceEqual(corruptPrimary),
            "commit_corrupt_primary_preserved");
        Check(File.ReadAllBytes(guardedRoots.CatalogBackupPath).SequenceEqual(guardedBackup),
            "commit_corrupt_primary_does_not_overwrite_backup");

        File.Copy(guardedRoots.CatalogBackupPath, guardedRoots.CatalogPath, overwrite: true);
        SetStorageVersion(guardedRoots.CatalogPath, 99);
        byte[] futurePrimary = File.ReadAllBytes(guardedRoots.CatalogPath);
        CatalogWriteResult futureWrite = guarded.Write(next);
        Check(futureWrite.Error == CatalogStoreError.UnsupportedStorageVersion,
            "commit_future_primary_refuses_write");
        Check(File.ReadAllBytes(guardedRoots.CatalogPath).SequenceEqual(futurePrimary),
            "commit_future_primary_preserved");
        Check(File.ReadAllBytes(guardedRoots.CatalogBackupPath).SequenceEqual(guardedBackup),
            "commit_future_primary_does_not_overwrite_backup");
    }

}
