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

internal static class DefectCatalogRecoveryTests
{
    public static void Run(StorageRootSet roots)
    {
        VerifyDefectCatalogHealthAndRestore(roots);
        VerifyInterruptedDefectRestore(roots);
    }

    private static void VerifyDefectCatalogHealthAndRestore(
        StorageRootSet parentRoots)
    {
        string healthBase = Path.Combine(
            parentRoots.LocalApplicationDataRoot,
            "defect-catalog-health");
        StorageRootSet healthRoots = StorageRootResolver.ResolveForTests(
            healthBase).Roots!;
        Guid healthFrameId = Guid.Parse("e4d63c51-532e-4d52-a41c-2212246a45e0");
        DefectSourceIdentity sourceIdentity = new(900, new string('c', 64));
        DefectRecipeSnapshot healthRecipe = DefectRecipeSnapshot.Create(
            healthFrameId,
            recipeRevision: 1,
            sourceIdentity,
            DefectRecipeItems());
        CatalogSnapshot healthCatalog = Snapshot(
            "health",
            DefectCatalogRow(healthFrameId, "health"));

        CatalogSessionOpenResult healthInitial = CatalogSession.Open(healthRoots);
        using (CatalogSession? initial = healthInitial.Session)
        {
            Check(healthInitial.IsSuccess, "defect_health_initial_open");
            if (initial is not null)
            {
                Check(initial.ReadOrCreate().IsSuccess,
                    "defect_health_initial_create");
                Check(initial.WriteDefectRecipe(healthRecipe).IsSuccess,
                    "defect_health_sidecar_first");
                Check(initial.Write(healthCatalog).IsSuccess,
                    "defect_health_catalog_after_sidecar");
                Check(initial.RemoveDefectRecipe(healthFrameId, 2).Error ==
                      DefectSidecarError.InvalidSnapshot,
                    "defect_health_remove_while_declared_blocked");
            }
        }

        CatalogSessionOpenResult healthyReopen = CatalogSession.Open(healthRoots);
        using (CatalogSession? healthy = healthyReopen.Session)
        {
            Check(healthyReopen.IsSuccess,
                "defect_health_restart_with_sidecar_opens");
            Check(healthy?.ReadDefectRecipe(healthFrameId).Snapshot?.RecipeRevision == 1,
                "defect_health_restart_reads_recipe");
        }

        string healthSidecarPath = DefectSidecarStore.PathFor(
            healthRoots,
            healthFrameId);
        byte[] healthyBytes = File.ReadAllBytes(healthSidecarPath);
        File.Delete(healthSidecarPath);
        CatalogSessionOpenResult missingOpen = CatalogSession.Open(healthRoots);
        missingOpen.Session?.Dispose();
        Check(missingOpen.Error == CatalogSessionError.MissingAuthoritativeData &&
              missingOpen.DefectSidecarError == DefectSidecarError.NotFound,
            "defect_health_missing_sidecar_blocks_library_open");

        File.WriteAllBytes(healthSidecarPath, healthyBytes);
        JsonObject damaged = JsonNode.Parse(healthyBytes)!.AsObject();
        damaged["recipeSHA256"] = new string('0', 64);
        File.WriteAllBytes(
            healthSidecarPath,
            CatalogJson.SerializeCanonical(damaged));
        CatalogSessionOpenResult damagedOpen = CatalogSession.Open(healthRoots);
        damagedOpen.Session?.Dispose();
        Check(damagedOpen.Error == CatalogSessionError.MissingAuthoritativeData &&
              damagedOpen.DefectSidecarError == DefectSidecarError.InvalidContent,
            "defect_health_damaged_sidecar_blocks_library_open");
        File.WriteAllBytes(healthSidecarPath, healthyBytes);

        string restoreBase = Path.Combine(
            parentRoots.LocalApplicationDataRoot,
            "defect-pending-restore");
        StorageRootSet restoreRoots = StorageRootResolver.ResolveForTests(
            restoreBase).Roots!;
        Guid selectedFrameId = Guid.Parse("9c7c5995-615b-4356-89de-e9440c36726c");
        Guid currentFrameId = Guid.Parse("d8f62712-9e03-46f6-b251-f66f0cd9a080");
        DateTimeOffset now = new(2026, 8, 10, 3, 0, 0, TimeSpan.Zero);
        string generationId = string.Empty;

        CatalogSessionOpenResult restoreInitial = CatalogSession.Open(restoreRoots);
        using (CatalogSession? restore = restoreInitial.Session)
        {
            Check(restoreInitial.IsSuccess, "defect_restore_initial_open");
            if (restore is not null)
            {
                Check(restore.ReadOrCreate().IsSuccess,
                    "defect_restore_initial_create");
                DefectRecipeSnapshot selectedRecipe = DefectRecipeSnapshot.Create(
                    selectedFrameId,
                    recipeRevision: 4,
                    sourceIdentity,
                    DefectRecipeItems());
                Check(restore.WriteDefectRecipe(selectedRecipe).IsSuccess &&
                      restore.Write(Snapshot(
                          "selected-defect",
                          DefectCatalogRow(selectedFrameId, "selected"))).IsSuccess,
                    "defect_restore_selected_generation_written");
                CatalogBackupCreateResult selectedBackup =
                    restore.CreateBackupForTesting(now);
                Check(selectedBackup.IsSuccess && selectedBackup.GenerationPath is not null,
                    "defect_restore_selected_generation_backed_up");
                generationId = selectedBackup.GenerationPath is null
                    ? string.Empty
                    : Path.GetFileName(selectedBackup.GenerationPath);

                DefectRecipeSnapshot currentRecipe = DefectRecipeSnapshot.Create(
                    currentFrameId,
                    recipeRevision: 7,
                    sourceIdentity,
                    [DefectRecipeItems()[1]]);
                Check(restore.WriteDefectRecipe(currentRecipe).IsSuccess &&
                      restore.Write(Snapshot(
                          "current-defect",
                          DefectCatalogRow(currentFrameId, "current"))).IsSuccess,
                    "defect_restore_current_generation_written");
                Check(restore.ScheduleRestoreForTesting(
                        generationId,
                        now.AddMinutes(1)).IsSuccess,
                    "defect_restore_schedule_with_sidecars");
            }
        }

        CatalogSessionOpenResult restoredOpen = CatalogSession.Open(restoreRoots);
        using (CatalogSession? restored = restoredOpen.Session)
        {
            Check(restoredOpen.IsSuccess &&
                  restored?.PendingRestoreApplication.Kind ==
                      CatalogPendingRestoreApplicationKind.Applied,
                "defect_restore_restart_applies_generation");
            Check(restored is not null &&
                  FrameOrder(restored.Read()) == selectedFrameId.ToString("D"),
                "defect_restore_catalog_and_sidecar_generation_match");
            Check(restored?.ReadDefectRecipe(selectedFrameId).Snapshot?.RecipeRevision == 4,
                "defect_restore_selected_recipe_restored");
            Check(restored?.ReadDefectRecipe(currentFrameId).Error ==
                  DefectSidecarError.NotFound,
                "defect_restore_replaces_previous_sidecar_set");
            Check(Directory.EnumerateDirectories(
                    restoreRoots.BackupRoot,
                    "backup-*",
                    SearchOption.TopDirectoryOnly)
                .Select(CatalogBackupStore.ValidateGeneration)
                .Any(value =>
                    value.Snapshot?.ActiveRollId == "current-defect" &&
                    value.Manifest?.DefectFrameIds.SequenceEqual(
                        [currentFrameId.ToString("D")]) == true),
                "defect_restore_safety_generation_preserves_previous_sidecar");
        }
    }

    /// <summary>
    /// Defects directory의 두 번째 move가 끝난 뒤 catalog commit 전에 프로세스가 끊긴 상태입니다.
    /// 다음 시작은 이미 새 sidecar가 live에 있다는 사실을 검증하고 commit만 재개해야 하며,
    /// 서로 맞지 않는 현재 catalog/sidecar 조합으로 safety backup을 만들면 안 됩니다.
    /// </summary>
    private static void VerifyInterruptedDefectRestore(StorageRootSet parentRoots)
    {
        string restoreBase = Path.Combine(
            parentRoots.LocalApplicationDataRoot,
            "defect-interrupted-restore");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(restoreBase).Roots!;
        Guid selectedFrameId = Guid.Parse("ed0b9d5e-7652-4fdf-b6c7-802abc4a9a2e");
        Guid currentFrameId = Guid.Parse("6cae1efe-f8ff-42ea-aec1-96fb6372d4de");
        DefectSourceIdentity identity = new(900, new string('d', 64));
        DateTimeOffset now = new(2026, 8, 14, 4, 0, 0, TimeSpan.Zero);
        string pendingPath = string.Empty;
        CatalogPendingRestoreMarker? marker = null;

        CatalogSessionOpenResult initialOpen = CatalogSession.Open(roots);
        using (CatalogSession? initial = initialOpen.Session)
        {
            Check(initialOpen.IsSuccess, "interrupted_restore_initial_open");
            if (initial is null)
            {
                return;
            }

            Check(initial.ReadOrCreate().IsSuccess,
                "interrupted_restore_initial_create");
            DefectRecipeSnapshot selectedRecipe = DefectRecipeSnapshot.Create(
                selectedFrameId,
                recipeRevision: 4,
                identity,
                DefectRecipeItems());
            Check(initial.WriteDefectRecipe(selectedRecipe).IsSuccess &&
                  initial.Write(Snapshot(
                      "interrupted-selected",
                      DefectCatalogRow(selectedFrameId, "selected"))).IsSuccess,
                "interrupted_restore_selected_written");
            CatalogBackupCreateResult selectedBackup = initial.CreateBackupForTesting(now);
            Check(selectedBackup.IsSuccess && selectedBackup.GenerationPath is not null,
                "interrupted_restore_selected_backed_up");

            DefectRecipeSnapshot currentRecipe = DefectRecipeSnapshot.Create(
                currentFrameId,
                recipeRevision: 7,
                identity,
                [DefectRecipeItems()[1]]);
            Check(initial.WriteDefectRecipe(currentRecipe).IsSuccess &&
                  initial.Write(Snapshot(
                      "interrupted-current",
                      DefectCatalogRow(currentFrameId, "current"))).IsSuccess,
                "interrupted_restore_current_written");
            string generationId = selectedBackup.GenerationPath is null
                ? string.Empty
                : Path.GetFileName(selectedBackup.GenerationPath);
            Check(initial.ScheduleRestoreForTesting(generationId, now.AddMinutes(1)).IsSuccess,
                "interrupted_restore_scheduled");
        }

        Check(CatalogPendingRestoreFiles.TryReadMarker(roots, out CatalogPendingRestoreMarker read) &&
              CatalogBackupStore.ValidateGeneration(
                  pendingPath = Path.Combine(roots.PendingRestoreRoot, read.DirectoryName))
                  .Manifest is not null,
            "interrupted_restore_pending_copy_valid");
        if (string.IsNullOrEmpty(pendingPath) ||
            !CatalogPendingRestoreFiles.TryReadMarker(roots, out marker) ||
            CatalogBackupStore.ValidateGeneration(pendingPath).Manifest is not { } manifest)
        {
            return;
        }

        // 실제 apply는 이 시점에서 현재 state를 safety generation으로 먼저 남깁니다.
        Check(CatalogBackupStore.Create(
                roots,
                now.AddMinutes(2),
                CatalogBackupStore.DefaultRetentionCount).IsSuccess,
            "interrupted_restore_safety_generation_exists");
        CatalogPendingRestoreError prepared = CatalogDefectRestoreTransaction.TryPrepare(
            roots,
            pendingPath,
            marker.DirectoryName,
            manifest,
            out CatalogDefectRestoreTransaction transaction);
        Check(prepared == CatalogPendingRestoreError.None &&
              transaction.Activate() == CatalogPendingRestoreError.None,
            "interrupted_restore_defect_swap_completed_before_kill");
        CatalogPendingRestoreError recovery =
            CatalogDefectRestoreTransaction.RecoverInterruptedActivation(
                roots,
                marker.DirectoryName,
                manifest,
                out CatalogDefectRestoreTransaction? recoveredTransaction);
        Check(recovery == CatalogPendingRestoreError.None && recoveredTransaction is not null,
            "interrupted_restore_recognizes_completed_defect_swap");
        Check(DefectSidecarStore.ValidateCatalogDeclarations(
                roots,
                CatalogBackupStore.ValidateGeneration(pendingPath).Snapshot!).IsHealthy,
            "interrupted_restore_swapped_defects_match_pending_catalog");

        // 여기서 process가 죽었다고 가정합니다. rollback/cleanup/marker 갱신을 호출하지 않은 채
        // 새 session을 열어, scheduled marker와 .previous artifact만으로 재개하는지 확인합니다.
        CatalogSessionOpenResult resumedOpen = CatalogSession.Open(roots);
        using (CatalogSession? resumed = resumedOpen.Session)
        {
            Check(resumedOpen.IsSuccess &&
                  resumed?.PendingRestoreApplication.Kind ==
                      CatalogPendingRestoreApplicationKind.Applied &&
                  resumed.PendingRestoreApplication.DidApplyRestore,
                "interrupted_restore_restart_resumes_catalog_commit");
            Check(resumed is not null &&
                  FrameOrder(resumed.Read()) == selectedFrameId.ToString("D") &&
                  resumed.ReadDefectRecipe(selectedFrameId).Snapshot?.RecipeRevision == 4,
                "interrupted_restore_catalog_and_defects_rejoin_selected_generation");
            Check(!File.Exists(CatalogPendingRestoreFiles.MarkerPath(roots)) &&
                  !Directory.EnumerateDirectories(
                      roots.LibraryRoot,
                      $".defects-{marker.DirectoryName}.*",
                      SearchOption.TopDirectoryOnly).Any(),
                "interrupted_restore_cleans_swap_artifacts_after_commit");
        }
    }

    private static CatalogEntityRow DefectCatalogRow(Guid frameId, string label) =>
        new(frameId.ToString("D"), new JsonObject
        {
            ["label"] = label,
            ["hasDefectEdits"] = true,
        });

}
