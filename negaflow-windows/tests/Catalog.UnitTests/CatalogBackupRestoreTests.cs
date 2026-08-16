using System.Diagnostics;
using System.IO.Compression;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.Data.Sqlite;
using static Negaflow.Catalog.UnitTests.CatalogTestAssert;
using static Negaflow.Catalog.UnitTests.CatalogStorageFixtures;

namespace Negaflow.Catalog.UnitTests;

using static Negaflow.Catalog.UnitTests.DefectTestFixture;

internal static class CatalogBackupRestoreTests
{
    public static void Run(StorageRootSet roots)
    {
        VerifyBackupGeneration(roots);
        VerifyPendingRestore(roots);
    }

    private static void VerifyBackupGeneration(StorageRootSet parentRoots)
    {
        string backupBase = Path.Combine(
            parentRoots.LocalApplicationDataRoot,
            "backup-generation");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(backupBase).Roots!;
        CatalogSessionOpenResult opened = CatalogSession.Open(roots);
        using CatalogSession? session = opened.Session;
        Check(opened.IsSuccess, "backup_session_open");
        if (session is null)
        {
            return;
        }

        DateTimeOffset now = new(2026, 8, 9, 12, 0, 0, TimeSpan.Zero);
        Check(session.ReadOrCreate().IsSuccess, "backup_initial_create");
        Check(session.Write(Snapshot("backup-a", Row("frame-1", "one"))).IsSuccess,
            "backup_first_catalog_write");

        CatalogBackupCreateResult first = session.CreateBackupForTesting(now);
        Check(first.IsSuccess && first.Sequence == 1, "backup_first_generation_created");
        Check(first.GenerationPath is not null && Directory.Exists(first.GenerationPath),
            "backup_first_generation_visible");
        Check(first.GenerationPath is not null &&
              CatalogBackupStore.ValidateGeneration(first.GenerationPath).IsValid,
            "backup_first_generation_validates");

        CatalogBackupCreateResult rejected = session.CreateBackupForTesting(
            now.AddMinutes(1),
            beforeValidation: staging => File.AppendAllText(
                Path.Combine(staging, "library.json"),
                " "));
        Check(rejected.Error == CatalogBackupError.ValidationFailed,
            "backup_invalid_staging_not_published");
        Check(!Directory.EnumerateDirectories(
                roots.BackupRoot,
                "staging-*",
                SearchOption.TopDirectoryOnly).Any(),
            "backup_failed_staging_cleaned");

        Guid defectFrameId = Guid.Parse("5de22616-5b54-4739-949e-1c2bfd6cf3ef");
        JsonObject defectPayload = new()
        {
            ["label"] = "defect",
            ["hasDefectEdits"] = true,
        };
        CatalogSnapshot defectCatalog = Snapshot(
                "backup-defect",
                new CatalogEntityRow(defectFrameId.ToString("D"), defectPayload));
        Check(session.Write(defectCatalog).Error ==
              CatalogStoreError.MissingAuthoritativeData,
            "backup_defect_catalog_write_requires_sidecar_first");

        DefectSourceIdentity sourceIdentity = new(321, new string('b', 64));
        DefectRecipeSnapshot defectRecipe = DefectRecipeSnapshot.Create(
            defectFrameId,
            recipeRevision: 1,
            sourceIdentity,
            DefectRecipeItems());
        Check(session.WriteDefectRecipe(defectRecipe).IsSuccess,
            "backup_defect_sidecar_write");
        Check(session.Write(defectCatalog).IsSuccess,
            "backup_defect_catalog_write_after_sidecar");
        File.Delete(DefectSidecarStore.PathFor(roots, defectFrameId));
        Check(session.CreateBackupForTesting(now.AddMinutes(2)).Error ==
              CatalogBackupError.DefectSidecarUnavailable,
            "backup_defect_without_sidecar_blocked");

        DefectRecipeSnapshot recoveredRecipe = DefectRecipeSnapshot.Create(
            defectFrameId,
            recipeRevision: 2,
            sourceIdentity,
            DefectRecipeItems());
        Check(session.WriteDefectRecipe(recoveredRecipe).IsSuccess,
            "backup_defect_sidecar_recovered");
        CatalogBackupCreateResult withDefect =
            session.CreateBackupForTesting(now.AddMinutes(2));
        Check(withDefect.IsSuccess && withDefect.Sequence == 2,
            "backup_defect_generation_created");
        Check(withDefect.GenerationPath is not null &&
              File.Exists(Path.Combine(
                  withDefect.GenerationPath,
                  "defects",
                  DefectSidecarStore.FileName(defectFrameId))) &&
              CatalogBackupStore.ValidateGeneration(withDefect.GenerationPath).IsValid,
            "backup_defect_sidecar_copied_and_validated");
        if (withDefect.GenerationPath is not null)
        {
            File.AppendAllText(
                Path.Combine(
                    withDefect.GenerationPath,
                    "defects",
                    DefectSidecarStore.FileName(defectFrameId)),
                " ");
            Check(!CatalogBackupStore.ValidateGeneration(
                    withDefect.GenerationPath).IsValid,
                "backup_defect_sidecar_hash_damage_rejected");
        }

        Check(session.Write(Snapshot("backup-b", Row("frame-2", "two"))).IsSuccess,
            "backup_second_catalog_write");
        CatalogBackupCreateResult second = session.CreateBackupForTesting(now.AddMinutes(3));
        Check(second.IsSuccess && second.Sequence == 3, "backup_second_sequence");
        Check(session.Write(Snapshot("backup-c", Row("frame-3", "three"))).IsSuccess,
            "backup_third_catalog_write");
        CatalogBackupCreateResult third = session.CreateBackupForTesting(now.AddMinutes(4));
        Check(third.IsSuccess && third.Sequence == 4, "backup_third_sequence");

        string future = Path.Combine(roots.BackupRoot, "backup-future-version");
        Directory.CreateDirectory(future);
        File.WriteAllBytes(
            Path.Combine(future, "manifest.json"),
            CatalogJson.SerializeCanonical(new JsonObject
            {
                ["version"] = 99,
                ["sequence"] = JsonValue.Create((ulong)99),
            }));

        Check(session.Write(Snapshot("backup-d", Row("frame-4", "four"))).IsSuccess,
            "backup_fourth_catalog_write");
        CatalogBackupCreateResult fourth = session.CreateBackupForTesting(now.AddMinutes(5));
        Check(fourth.IsSuccess && fourth.Sequence == 100,
            "backup_future_manifest_keeps_sequence_monotonic");
        Check(Directory.Exists(future), "backup_future_generation_not_pruned");
        Check(first.GenerationPath is not null && !Directory.Exists(first.GenerationPath),
            "backup_retention_prunes_oldest_valid_generation");

        string[] valid = Directory.EnumerateDirectories(
                roots.BackupRoot,
                "backup-*",
                SearchOption.TopDirectoryOnly)
            .Where(path => CatalogBackupStore.ValidateGeneration(path).IsValid)
            .ToArray();
        Check(valid.Length == CatalogBackupStore.DefaultRetentionCount,
            "backup_retention_keeps_three_valid_generations");

        if (fourth.GenerationPath is not null)
        {
            File.AppendAllText(Path.Combine(fourth.GenerationPath, "library.json"), " ");
            Check(!CatalogBackupStore.ValidateGeneration(fourth.GenerationPath).IsValid,
                "backup_hash_damage_is_rejected");
        }
    }

    private static void VerifyPendingRestore(StorageRootSet parentRoots)
    {
        DateTimeOffset now = new(2026, 8, 9, 14, 0, 0, TimeSpan.Zero);

        string pinningBase = Path.Combine(
            parentRoots.LocalApplicationDataRoot,
            "pending-restore-pinning");
        StorageRootSet pinningRoots = StorageRootResolver.ResolveForTests(
            pinningBase).Roots!;
        CatalogSessionOpenResult pinningOpen = CatalogSession.Open(pinningRoots);
        using (CatalogSession? pinning = pinningOpen.Session)
        {
            Check(pinningOpen.IsSuccess, "pending_pinning_session_open");
            if (pinning is not null)
            {
                Check(pinning.ReadOrCreate().IsSuccess,
                    "pending_pinning_initial_create");
                Check(pinning.Write(Snapshot(
                        "restore-selected",
                        Row("frame-selected", "selected"))).IsSuccess,
                    "pending_pinning_selected_write");
                CatalogBackupCreateResult selected =
                    pinning.CreateBackupForTesting(now);
                Check(selected.IsSuccess && selected.GenerationPath is not null,
                    "pending_pinning_source_created");
                Check(pinning.Write(Snapshot(
                        "restore-live",
                        Row("frame-live", "live"))).IsSuccess,
                    "pending_pinning_live_write");

                string generationId = selected.GenerationPath is null
                    ? string.Empty
                    : Path.GetFileName(selected.GenerationPath);
                CatalogPendingRestoreScheduleResult scheduled =
                    pinning.ScheduleRestoreForTesting(
                        generationId,
                        now.AddMinutes(1));
                Check(scheduled.IsSuccess,
                    "pending_pinning_schedule_success");
                Check(FrameLabels(pinning.Read()) == "live",
                    "pending_pinning_does_not_replace_live_session");

                if (selected.GenerationPath is not null &&
                    Directory.Exists(selected.GenerationPath))
                {
                    Directory.Delete(selected.GenerationPath, recursive: true);
                }
                bool markerRead = CatalogPendingRestoreFiles.TryReadMarker(
                    pinningRoots,
                    out CatalogPendingRestoreMarker pinnedMarker);
                Check(markerRead, "pending_pinning_marker_readback");
                string pinnedPath = markerRead
                    ? Path.Combine(
                        pinningRoots.PendingRestoreRoot,
                        pinnedMarker.DirectoryName)
                    : string.Empty;
                Check(markerRead &&
                      CatalogBackupStore.ValidateGeneration(pinnedPath).IsValid,
                    "pending_pinning_survives_source_removal");

                Check(pinning.CancelScheduledRestore().IsSuccess,
                    "pending_pinning_cancel_success");
                Check(!File.Exists(CatalogPendingRestoreFiles.MarkerPath(
                        pinningRoots)),
                    "pending_pinning_cancel_removes_marker");
                Check(string.IsNullOrEmpty(pinnedPath) || !Directory.Exists(pinnedPath),
                    "pending_pinning_cancel_removes_copy");
            }
        }

        string applyBase = Path.Combine(
            parentRoots.LocalApplicationDataRoot,
            "pending-restore-apply");
        StorageRootSet applyRoots = StorageRootResolver.ResolveForTests(applyBase).Roots!;
        CatalogSessionOpenResult applyInitialOpen = CatalogSession.Open(applyRoots);
        using (CatalogSession? initial = applyInitialOpen.Session)
        {
            Check(applyInitialOpen.IsSuccess, "pending_apply_initial_session_open");
            if (initial is not null)
            {
                Check(initial.ReadOrCreate().IsSuccess,
                    "pending_apply_initial_create");
                Check(initial.Write(Snapshot(
                        "restore-selected",
                        Row("frame-selected", "selected"))).IsSuccess,
                    "pending_apply_selected_write");
                CatalogBackupCreateResult selected =
                    initial.CreateBackupForTesting(now);
                Check(initial.Write(Snapshot(
                        "restore-current",
                        Row("frame-current", "current"))).IsSuccess,
                    "pending_apply_current_write");
                string generationId = selected.GenerationPath is null
                    ? string.Empty
                    : Path.GetFileName(selected.GenerationPath);
                Check(initial.ScheduleRestoreForTesting(
                        generationId,
                        now.AddMinutes(1)).IsSuccess,
                    "pending_apply_schedule_success");
                Check(FrameLabels(initial.Read()) == "current",
                    "pending_apply_current_visible_until_restart");
            }
        }

        CatalogSessionOpenResult appliedOpen = CatalogSession.Open(applyRoots);
        using (CatalogSession? applied = appliedOpen.Session)
        {
            Check(appliedOpen.IsSuccess, "pending_apply_restart_open");
            if (applied is not null)
            {
                Check(applied.PendingRestoreApplication.Kind ==
                      CatalogPendingRestoreApplicationKind.Applied &&
                      applied.PendingRestoreApplication.DidApplyRestore,
                    "pending_apply_reports_application");
                Check(FrameLabels(applied.Read()) == "selected",
                    "pending_apply_selected_generation_visible");
                Check(!File.Exists(CatalogPendingRestoreFiles.MarkerPath(applyRoots)),
                    "pending_apply_marker_cleaned");
                Check(!Directory.Exists(applyRoots.PendingRestoreRoot) ||
                      !Directory.EnumerateDirectories(
                          applyRoots.PendingRestoreRoot,
                          "restore-*",
                          SearchOption.TopDirectoryOnly).Any(),
                    "pending_apply_copy_cleaned");
                Check(Directory.EnumerateDirectories(
                        applyRoots.BackupRoot,
                        "backup-*",
                        SearchOption.TopDirectoryOnly)
                    .Select(CatalogBackupStore.ValidateGeneration)
                    .Any(validation =>
                        validation.Snapshot?.ActiveRollId == "restore-current"),
                    "pending_apply_preserves_current_as_safety_generation");
            }
        }

        string futureBase = Path.Combine(
            parentRoots.LocalApplicationDataRoot,
            "pending-restore-future");
        StorageRootSet futureRoots = StorageRootResolver.ResolveForTests(futureBase).Roots!;
        CatalogSessionOpenResult futureInitialOpen = CatalogSession.Open(futureRoots);
        using (CatalogSession? initial = futureInitialOpen.Session)
        {
            Check(futureInitialOpen.IsSuccess, "pending_future_initial_open");
            if (initial is not null)
            {
                Check(initial.ReadOrCreate().IsSuccess,
                    "pending_future_initial_create");
                Check(initial.Write(Snapshot(
                        "future-selected",
                        Row("frame-selected", "selected"))).IsSuccess,
                    "pending_future_selected_write");
                CatalogBackupCreateResult selected =
                    initial.CreateBackupForTesting(now);
                Check(initial.Write(Snapshot(
                        "future-current",
                        Row("frame-current", "current"))).IsSuccess,
                    "pending_future_current_write");
                string generationId = selected.GenerationPath is null
                    ? string.Empty
                    : Path.GetFileName(selected.GenerationPath);
                Check(initial.ScheduleRestoreForTesting(
                        generationId,
                        now.AddMinutes(1)).IsSuccess,
                    "pending_future_schedule_success");
            }
        }
        SetStorageVersion(futureRoots.CatalogPath, 99);
        byte[] futureBytes = File.ReadAllBytes(futureRoots.CatalogPath);
        CatalogSessionOpenResult blockedFuture = CatalogSession.Open(futureRoots);
        blockedFuture.Session?.Dispose();
        Check(blockedFuture.Error == CatalogSessionError.PendingRestoreFailed &&
              blockedFuture.PendingRestoreError ==
                  CatalogPendingRestoreError.UnsupportedCurrentCatalog &&
              blockedFuture.ObservedVersion == 99,
            "pending_future_blocks_downgrade");
        Check(File.ReadAllBytes(futureRoots.CatalogPath).SequenceEqual(futureBytes),
            "pending_future_preserves_primary_bytes");
        bool futureMarkerRead = CatalogPendingRestoreFiles.TryReadMarker(
            futureRoots,
            out CatalogPendingRestoreMarker futureMarker);
        Check(futureMarkerRead &&
              Directory.Exists(Path.Combine(
                  futureRoots.PendingRestoreRoot,
                  futureMarker.DirectoryName)),
            "pending_future_preserves_marker_and_copy");

        string cleanupBase = Path.Combine(
            parentRoots.LocalApplicationDataRoot,
            "pending-restore-cleanup");
        StorageRootSet cleanupRoots = StorageRootResolver.ResolveForTests(
            cleanupBase).Roots!;
        CatalogSessionOpenResult cleanupInitialOpen = CatalogSession.Open(cleanupRoots);
        using (CatalogSession? initial = cleanupInitialOpen.Session)
        {
            Check(cleanupInitialOpen.IsSuccess, "pending_cleanup_initial_open");
            if (initial is not null)
            {
                Check(initial.ReadOrCreate().IsSuccess,
                    "pending_cleanup_initial_create");
                Check(initial.Write(Snapshot(
                        "cleanup-selected",
                        Row("frame-selected", "selected"))).IsSuccess,
                    "pending_cleanup_selected_write");
                CatalogBackupCreateResult selected =
                    initial.CreateBackupForTesting(now);
                Check(initial.Write(Snapshot(
                        "cleanup-current",
                        Row("frame-current", "current"))).IsSuccess,
                    "pending_cleanup_current_write");
                string generationId = selected.GenerationPath is null
                    ? string.Empty
                    : Path.GetFileName(selected.GenerationPath);
                Check(initial.ScheduleRestoreForTesting(
                        generationId,
                        now.AddMinutes(1)).IsSuccess,
                    "pending_cleanup_schedule_success");
            }
        }

        CatalogPendingRestoreCleanup markerFailure = new(
            RemoveDirectory: path =>
            {
                if (!CatalogPendingRestoreFiles.TryDeleteGenerationCopy(
                        path,
                        cleanupRoots.PendingRestoreRoot,
                        "restore-",
                        requireValidGeneration: true))
                {
                    throw new IOException("injected cleanup setup failure");
                }
            },
            RemoveMarker: _ => throw new IOException(
                "injected marker delete failure"));
        CatalogSessionOpenResult cleanupPendingOpen = CatalogSession.OpenForTesting(
            cleanupRoots,
            markerFailure);
        int validGenerationCount;
        using (CatalogSession? cleanupPending = cleanupPendingOpen.Session)
        {
            Check(cleanupPendingOpen.IsSuccess,
                "pending_cleanup_failure_still_opens_session");
            Check(cleanupPending?.PendingRestoreApplication.Kind ==
                      CatalogPendingRestoreApplicationKind.CleanupPending &&
                  cleanupPending.PendingRestoreApplication.DidApplyRestore,
                "pending_cleanup_failure_reports_applied_cleanup_pending");
            Check(cleanupPending is not null &&
                  FrameLabels(cleanupPending.Read()) == "selected",
                "pending_cleanup_failure_keeps_applied_catalog");
            Check(CatalogPendingRestoreFiles.TryReadMarker(
                    cleanupRoots,
                    out CatalogPendingRestoreMarker appliedMarker) &&
                  appliedMarker.Phase == CatalogPendingRestorePhase.Applied,
                "pending_cleanup_failure_persists_applied_fence");
            validGenerationCount = Directory.EnumerateDirectories(
                    cleanupRoots.BackupRoot,
                    "backup-*",
                    SearchOption.TopDirectoryOnly)
                .Count(path => CatalogBackupStore.ValidateGeneration(path).IsValid);
        }

        CatalogSessionOpenResult cleanupRetryOpen = CatalogSession.Open(cleanupRoots);
        using (CatalogSession? cleanupRetry = cleanupRetryOpen.Session)
        {
            Check(cleanupRetryOpen.IsSuccess,
                "pending_cleanup_retry_session_open");
            Check(cleanupRetry?.PendingRestoreApplication.Kind ==
                      CatalogPendingRestoreApplicationKind.CleanupOnly &&
                  !cleanupRetry.PendingRestoreApplication.DidApplyRestore,
                "pending_cleanup_retry_is_cleanup_only");
            Check(!File.Exists(CatalogPendingRestoreFiles.MarkerPath(cleanupRoots)),
                "pending_cleanup_retry_removes_marker");
            Check(Directory.EnumerateDirectories(
                    cleanupRoots.BackupRoot,
                    "backup-*",
                    SearchOption.TopDirectoryOnly)
                .Count(path => CatalogBackupStore.ValidateGeneration(path).IsValid) ==
                validGenerationCount,
                "pending_cleanup_retry_does_not_create_safety_generation");
        }
    }


}
