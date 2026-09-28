using System.Text.Json.Nodes;
using Negaflow.Catalog;
using Negaflow.Shell.UnitTests.Defects;
using static Negaflow.Shell.UnitTests.TestAssert;
using static Negaflow.Shell.UnitTests.TestFrameFactory;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 진단 패널의 카탈로그 수동 복구·재설치입니다. macOS <c>LibraryCatalogMaintenanceTests</c> 를
/// Windows 에서 같은 증상이 나는 모양으로 옮겼습니다: 열린 뒤 결함 기록(sidecar)이 사라지거나
/// 깨지면 카탈로그 커밋 게이트가 이후의 저장을 전부 막고, 종료 저장까지 막혀 앱을 닫을 수 없습니다.
/// </summary>
internal static class LibraryCatalogMaintenanceTests
{
    private static readonly LibraryCatalogMaintenanceBusy Idle = default;

    internal static void Run()
    {
        MetadataOnlySidecarChangeDoesNotBlockSave();
        RepairRewritesMissingSidecarAndQuitCommits();
        RepairRewritesCorruptSidecarFromMemory();
        RepairLeavesRecipeThatCannotBeReplaced();
        ReinstallSchedulesVerifiedRestoreThatNextOpenApplies();
        MissingRecordAtOpenIsRestorePending();
        RestorePendingComesBackWhenRecordReturns();
        RestorePendingKeepsNewerRecord();
        RecipeWriteFailuresAreReported();
        MaintenanceDoesNothingWhileBusy();
    }

    /// <summary>
    /// 백업·동기화 도구가 수정 시각만 바꾼 경우입니다. 검증 캐시는 어긋나지만 내용이 같으므로
    /// 버튼 없이도 저장이 막히면 안 됩니다(macOS ad683f44 와 같은 보장).
    /// </summary>
    private static void MetadataOnlySidecarChangeDoesNotBlockSave()
    {
        RunIsolated("metadata", (roots, frameId) =>
        {
            using LibraryHostService host = OpenHost(roots, "maintenance_metadata_open");
            File.SetLastWriteTimeUtc(Sidecar(roots, frameId), DateTime.UtcNow.AddHours(-1));
            Check(host.Save() == CatalogStoreError.None,
                "maintenance_metadata_only_change_does_not_block_save");
        });
    }

    private static void RepairRewritesMissingSidecarAndQuitCommits()
    {
        RunIsolated("missing", (roots, frameId) =>
        {
            using (LibraryHostService host = OpenHost(roots, "maintenance_missing_open"))
            {
                ulong previous = host.Frames.Single().DefectRecipe!.RecipeRevision;
                File.Delete(Sidecar(roots, frameId));
                Check(host.Save() == CatalogStoreError.MissingAuthoritativeData,
                    "maintenance_missing_sidecar_blocks_save");
                // 진단 "저장 오류" 줄이 읽는 값입니다(macOS libraryCatalogPersistenceError).
                Check(host.LastSaveError == CatalogStoreError.MissingAuthoritativeData,
                    "maintenance_missing_sidecar_save_error_is_kept",
                    () => host.LastSaveError.ToString());
                // 진단 패널의 "최근 실패 이벤트" 에 macOS 와 같은 코드로 남아야 합니다.
                Check(LastCatalogSaveFailureCode() == "catalog_snapshot_invalid.defect_sidecar_mismatch",
                    "maintenance_missing_sidecar_is_reported",
                    () => LastCatalogSaveFailureCode() ?? "none");
                Check(!Quit(host).IsSuccess, "maintenance_missing_sidecar_blocks_quit");

                LibraryCatalogMaintenanceResult repaired = host.RepairCatalog(Idle);

                Check(repaired.IsSuccess, "maintenance_repair_succeeds",
                    () => $"{repaired.Error} {repaired.CatalogError} {repaired.SidecarError}");
                DefectRecipeSnapshot memory = host.Frames.Single().DefectRecipe!;
                Check(memory.Items.Count == 1 && memory.RecipeRevision > previous,
                    "maintenance_repair_raises_the_revision",
                    () => $"{previous} -> {memory.RecipeRevision}");
                Check(ReadSidecar(roots, frameId) is { } stored &&
                      stored.Revision == memory.RecipeRevision &&
                      stored.Sha256 == memory.RecipeSha256 && stored.Items == 1,
                    "maintenance_repair_rewrites_the_sidecar");
                Check(host.Save() == CatalogStoreError.None &&
                      host.LastSaveError == CatalogStoreError.None,
                    "maintenance_repair_unblocks_save");
                // 재실행은 정상 종료 경로(카탈로그 커밋)를 거칩니다. 그게 통과해야 앱이 다시 열립니다.
                Check(Quit(host).IsSuccess, "maintenance_repair_lets_quit_commit");
            }
            using LibraryHostService reopened = OpenHost(roots, "maintenance_missing_reopen");
            Check(reopened.Frames.Single().DefectRecipe?.Items.Count == 1,
                "maintenance_repair_survives_reopen");
        });
    }

    private static void RepairRewritesCorruptSidecarFromMemory()
    {
        RunIsolated("corrupt", (roots, frameId) =>
        {
            using LibraryHostService host = OpenHost(roots, "maintenance_corrupt_open");
            File.WriteAllText(Sidecar(roots, frameId), "not a sidecar");
            Check(host.Save() != CatalogStoreError.None, "maintenance_corrupt_sidecar_blocks_save");

            Check(host.RepairCatalog(Idle).IsSuccess, "maintenance_corrupt_repair_succeeds");
            Check(ReadSidecar(roots, frameId)?.Items == 1,
                "maintenance_corrupt_sidecar_is_rewritten_from_memory");
            Check(host.Save() == CatalogStoreError.None, "maintenance_corrupt_repair_unblocks_save");
            // 깨진 파일은 덮기 전에 원본 그대로 보관합니다.
            string? preserved = Directory.EnumerateDirectories(roots.LibraryRoot, "defects.corrupt-*")
                .FirstOrDefault();
            Check(preserved is not null &&
                  File.ReadAllText(Path.Combine(preserved, $"{frameId:D}.json")) == "not a sidecar",
                "maintenance_corrupt_sidecar_is_preserved_before_rewrite");
        });
    }

    /// <summary>
    /// 더 새 버전 기록과 지금 읽을 수 없는 기록은 건드리지 않고 실패합니다 — 비우거나 덮으면
    /// 되돌릴 수 없습니다.
    /// </summary>
    private static void RepairLeavesRecipeThatCannotBeReplaced()
    {
        RunIsolated("newer", (roots, frameId) =>
        {
            using LibraryHostService host = OpenHost(roots, "maintenance_newer_open");
            string path = Sidecar(roots, frameId);
            JsonObject newer = JsonNode.Parse(File.ReadAllText(path))!.AsObject();
            newer["version"] = newer["version"]!.GetValue<int>() + 1;
            File.WriteAllText(path, newer.ToJsonString());
            byte[] before = File.ReadAllBytes(path);

            LibraryCatalogMaintenanceResult result = host.RepairCatalog(Idle);

            Check(result.Error == LibraryCatalogMaintenanceError.DefectRecipeRewriteFailed &&
                  result.SidecarError == DefectSidecarError.UnsupportedVersion,
                "maintenance_newer_recipe_is_kept",
                () => $"{result.Error} {result.SidecarError}");
            Check(File.ReadAllBytes(path).SequenceEqual(before),
                "maintenance_newer_recipe_file_is_untouched");
        });
        RunIsolated("locked", (roots, frameId) =>
        {
            using LibraryHostService host = OpenHost(roots, "maintenance_locked_open");
            string path = Sidecar(roots, frameId);
            byte[] before = File.ReadAllBytes(path);
            LibraryCatalogMaintenanceResult result;
            using (new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.None))
            {
                result = host.RepairCatalog(Idle);
            }
            Check(!result.IsSuccess, "maintenance_unreadable_recipe_fails",
                () => result.Error.ToString());
            Check(File.ReadAllBytes(path).SequenceEqual(before),
                "maintenance_unreadable_recipe_file_is_untouched");
        });
    }

    private static void ReinstallSchedulesVerifiedRestoreThatNextOpenApplies()
    {
        RunIsolated("reinstall", (roots, frameId) =>
        {
            IReadOnlyList<Guid> editIds;
            using (LibraryHostService host = OpenHost(roots, "maintenance_reinstall_open"))
            {
                editIds = [.. host.Frames.Single().DefectRecipe!.Items.Select(item => item.Id)];
                File.Delete(Sidecar(roots, frameId));
                Check(host.Save() != CatalogStoreError.None,
                    "maintenance_reinstall_starts_blocked");

                LibraryCatalogMaintenanceResult reinstalled = host.ReinstallCatalog(Idle);

                Check(reinstalled.IsSuccess, "maintenance_reinstall_succeeds",
                    () => reinstalled.Error.ToString());
                Check(host.IsCatalogReinstallPendingRelaunch &&
                      CatalogRecovery.PendingRestoreGenerationId(roots) is not null,
                    "maintenance_reinstall_schedules_a_restore");
                // 기록이 사라진 사진이 있어 커밋은 실패할 상태지만, 예약한 세대가 다음 실행에서
                // 카탈로그를 덮으므로 커밋 없이 바로 종료돼야 합니다.
                Check(Quit(host).IsSuccess, "maintenance_reinstall_quits_without_commit");
            }

            using LibraryHostService relaunched = OpenHost(roots, "maintenance_reinstall_reopen");
            Check(CatalogRecovery.PendingRestoreGenerationId(roots) is null,
                "maintenance_reinstall_is_applied_on_open");
            LibraryFrameSnapshot restored = relaunched.Frames.Single();
            Check(restored.DefectRecipe?.Items.Select(item => item.Id).SequenceEqual(editIds) == true,
                "maintenance_reinstall_restores_defect_edits");
            Check(relaunched.Save() == CatalogStoreError.None,
                "maintenance_reinstall_saves_after_open");
            // 검증된 세대로 못 만드는 지금 파일(결함 기록이 사라짐)은 원본 그대로 보관됩니다.
            Check(Directory.EnumerateFiles(roots.LibraryRoot, "library.corrupt-*").Any(),
                "maintenance_reinstall_preserves_the_broken_catalog");
        });
    }

    /// <summary>
    /// 앱을 끈 사이 결함 기록이 사라진 경우입니다. macOS 처럼 라이브러리는 열리고 그 사진만 "복원
    /// 대기" 입니다 — 예전에는 기록 하나 때문에 라이브러리 전체가 열리지 않았습니다. 복원 대기
    /// 사진은 현상하지 않고, 저장은 막히며, 수동 복구가 원본을 보관한 뒤 그 사진의 편집만 비웁니다.
    /// </summary>
    private static void MissingRecordAtOpenIsRestorePending()
    {
        RunIsolated("pending-lost", (roots, frameId) =>
        {
            File.Delete(Sidecar(roots, frameId));
            using (LibraryHostService host = OpenHost(roots, "maintenance_pending_opens"))
            {
                LibraryFrameSnapshot frame = host.Frames.Single();
                Check(frame.DefectRestorePending && frame.DefectRecipe is null,
                    "maintenance_pending_frame_stays_in_the_library");
                Check(DevelopRequestFactory.Create(frame, Path.Combine(Path.GetTempPath(), "pending.png"))
                        .Refusal == DevelopRequestRefusal.DefectRestorePending,
                    "maintenance_pending_frame_is_not_developed");
                Check(host.Save() == CatalogStoreError.MissingAuthoritativeData,
                    "maintenance_pending_frame_blocks_save");

                LibraryCatalogMaintenanceResult repaired = host.RepairCatalog(Idle);
                Check(repaired.IsSuccess, "maintenance_pending_repair_succeeds",
                    () => $"{repaired.Error} {repaired.CatalogError} {repaired.SidecarError}");
                LibraryFrameSnapshot settled = host.Frames.Single();
                Check(!settled.DefectRestorePending && settled.DefectRecipe is null,
                    "maintenance_pending_repair_clears_the_lost_edits");
                Check(Directory.EnumerateFiles(roots.LibraryRoot, "library.corrupt-*").Any(),
                    "maintenance_pending_repair_preserves_the_catalog");
                Check(host.Save() == CatalogStoreError.None && Quit(host).IsSuccess,
                    "maintenance_pending_repair_unblocks_save_and_quit");
            }
            using LibraryHostService reopened = OpenHost(roots, "maintenance_pending_reopens");
            Check(reopened.Frames.Single() is { DefectRestorePending: false, DefectRecipe: null },
                "maintenance_pending_repair_survives_reopen");
        });
    }

    /// <summary>기록이 돌아오면(동기화 도구가 되살림 등) 수동 복구가 편집을 그대로 되살립니다.</summary>
    private static void RestorePendingComesBackWhenRecordReturns()
    {
        RunIsolated("pending-restored", (roots, frameId) =>
        {
            string sidecar = Sidecar(roots, frameId);
            byte[] kept = File.ReadAllBytes(sidecar);
            File.Delete(sidecar);
            using LibraryHostService host = OpenHost(roots, "maintenance_pending_restored_opens");
            Check(host.Frames.Single().DefectRestorePending, "maintenance_pending_restored_starts_pending");
            File.WriteAllBytes(sidecar, kept);
            Check(host.RepairCatalog(Idle).IsSuccess &&
                  host.Frames.Single() is { DefectRestorePending: false, DefectRecipe.Items.Count: 1 },
                "maintenance_pending_restored_brings_the_edits_back");
            Check(host.Save() == CatalogStoreError.None, "maintenance_pending_restored_saves");
        });
    }

    /// <summary>더 새 버전 기록은 되살리지도 비우지도 않고 실패합니다 — 비우면 되돌릴 수 없습니다.</summary>
    private static void RestorePendingKeepsNewerRecord()
    {
        RunIsolated("pending-newer", (roots, frameId) =>
        {
            string path = Sidecar(roots, frameId);
            JsonObject newer = JsonNode.Parse(File.ReadAllText(path))!.AsObject();
            newer["version"] = newer["version"]!.GetValue<int>() + 1;
            File.WriteAllText(path, newer.ToJsonString());
            byte[] before = File.ReadAllBytes(path);
            using LibraryHostService host = OpenHost(roots, "maintenance_pending_newer_opens");
            Check(host.Frames.Single().DefectRestorePending, "maintenance_pending_newer_starts_pending");
            LibraryCatalogMaintenanceResult result = host.RepairCatalog(Idle);
            Check(result.Error == LibraryCatalogMaintenanceError.DefectRecipeRewriteFailed &&
                  result.SidecarError == DefectSidecarError.UnsupportedVersion &&
                  host.Frames.Single().DefectRestorePending &&
                  File.ReadAllBytes(path).AsSpan().SequenceEqual(before),
                "maintenance_pending_newer_is_left_alone",
                () => $"{result.Error} {result.SidecarError}");
        });
    }

    /// <summary>
    /// macOS <c>recordDefectSidecarWriteFailure</c> 처럼, 결함 기록이 저장되지 않은 까닭이 진단
    /// "최근 실패 이벤트" 에 남아야 합니다. 다음 revision 이 아닌 기록도 저장되지 않은 것입니다.
    /// </summary>
    private static void RecipeWriteFailuresAreReported()
    {
        RunIsolated("write-failure", (roots, frameId) =>
        {
            using LibraryDocument document = LibraryDocument.Open(roots).Document!;
            DefectRecipeSnapshot same = DefectRecipeSnapshot.Create(
                frameId, 4, null, [DefectRecipeSamples.Edit(DefectEditKind.Brush)]);
            Check(!document.WriteDefectRecipe(frameId.ToString("D"), same).IsSuccess &&
                  LastCatalogSaveFailureCode() == "defect_sidecar_write_failed.RevisionNotNext",
                "maintenance_recipe_revision_rejection_is_reported",
                () => LastCatalogSaveFailureCode() ?? "none");

            // 결함 폴더 자리가 파일이면 기록을 쓸 수 없습니다.
            Directory.Delete(roots.DefectRecipeRoot, recursive: true);
            File.WriteAllText(roots.DefectRecipeRoot, "not a folder");
            DefectRecipeSnapshot next = DefectRecipeSnapshot.Create(
                frameId, 5, null, [DefectRecipeSamples.Edit(DefectEditKind.Brush)]);
            bool written = document.WriteDefectRecipe(frameId.ToString("D"), next).IsSuccess;
            string? code = LastCatalogSaveFailureCode();
            Check(!written &&
                  code is not null &&
                  code.StartsWith("defect_sidecar_write_failed.", StringComparison.Ordinal) &&
                  code != "defect_sidecar_write_failed.RevisionNotNext",
                "maintenance_recipe_write_failure_is_reported",
                () => code ?? "none");
        });
    }

    private static void MaintenanceDoesNothingWhileBusy()
    {
        RunIsolated("busy", (roots, frameId) =>
        {
            using LibraryHostService host = OpenHost(roots, "maintenance_busy_open");
            File.Delete(Sidecar(roots, frameId));
            LibraryCatalogMaintenanceBusy scanning = Idle with { Scanning = true };

            Check(!host.CanRunCatalogMaintenance(scanning), "maintenance_blocked_while_scanning");
            Check(host.RepairCatalog(scanning).Error == LibraryCatalogMaintenanceError.Unavailable &&
                  host.ReinstallCatalog(scanning).Error == LibraryCatalogMaintenanceError.Unavailable,
                "maintenance_does_nothing_while_scanning");
            Check(!host.IsCatalogReinstallPendingRelaunch &&
                  CatalogRecovery.PendingRestoreGenerationId(roots) is null &&
                  !File.Exists(Sidecar(roots, frameId)),
                "maintenance_busy_leaves_files_alone");
        });
        using var closed = new LibraryHostService(
            new FakeDispatcher(accepts: true),
            new ScannerWorkflowTests.ThrowingDevelopExporter(),
            ReadMetadata);
        Check(!closed.CanRunCatalogMaintenance(Idle) &&
              closed.RepairCatalog(Idle).Error == LibraryCatalogMaintenanceError.Unavailable,
            "maintenance_needs_an_open_library");
    }

    private static string? LastCatalogSaveFailureCode() =>
        Negaflow.Shell.Diagnostics.AppDiagnostics.RecentEvents.LastOrDefault(item =>
            item.Operation == Negaflow.Shell.Diagnostics.AppDiagnosticOperation.CatalogSave &&
            item.Phase == Negaflow.Shell.Diagnostics.AppDiagnosticPhase.Error)?.Code;

    private static LibraryDefectTerminationResult Quit(LibraryHostService host) =>
        host.PrepareForTerminationAsync(Path.GetTempPath()).GetAwaiter().GetResult();

    private static LibraryHostService OpenHost(StorageRootSet roots, string label)
    {
        var host = new LibraryHostService(
            new FakeDispatcher(accepts: true),
            new ScannerWorkflowTests.ThrowingDevelopExporter(),
            ReadMetadata);
        Check(host.Open(roots) == LibraryHostState.Open, label);
        return host;
    }

    private static string Sidecar(StorageRootSet roots, Guid frameId) =>
        Path.Combine(roots.DefectRecipeRoot, $"{frameId:D}.json");

    /// <summary>
    /// sidecar 의 revision·지문·항목 수입니다. 열린 호스트가 카탈로그 잠금을 들고 있어 세션을 새로
    /// 열 수 없으므로 JSON 을 직접 읽습니다. 못 읽으면 <see langword="null"/> 입니다.
    /// </summary>
    private static (ulong Revision, string Sha256, int Items)? ReadSidecar(
        StorageRootSet roots,
        Guid frameId)
    {
        try
        {
            JsonObject root = JsonNode.Parse(File.ReadAllText(Sidecar(roots, frameId)))!.AsObject();
            return (
                root["recipeRevision"]!.GetValue<ulong>(),
                root["recipeSHA256"]!.GetValue<string>(),
                root["items"]!.AsArray().Count);
        }
        catch (Exception error) when (error is IOException or System.Text.Json.JsonException or
            InvalidOperationException or NullReferenceException or FormatException)
        {
            return null;
        }
    }

    private static LibrarySourceMetadata? ReadMetadata(string path) =>
        new LibrarySourceMetadata(16, 4, 2, 3, 16, 1, 1);

    /// <summary>결함 편집이 하나 있는 사진 한 장짜리 라이브러리를 만듭니다.</summary>
    private static void RunIsolated(string name, Action<StorageRootSet, Guid> test)
    {
        string parent = Path.Combine(Path.GetTempPath(), "negaflow-catalog-maintenance-tests");
        string isolatedBase = Path.Combine(parent, $"{name}-{Guid.NewGuid():N}");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;
        Guid frameId = Guid.NewGuid();
        try
        {
            string source = Path.Combine(isolatedBase, "sources", "MAINTENANCE.tiff");
            Directory.CreateDirectory(Path.GetDirectoryName(source)!);
            File.WriteAllBytes(source, new byte[16]);
            JsonObject record = FrameRecord(frameId.ToString("D"), "MAINTENANCE.tiff", exposure: 0.0);
            record["rawScanPath"] = source;
            record[LibraryFrameReader.SourceMetadataName] =
                LibrarySourceMetadataJson.Write(ReadMetadata(source)!.Value);
            DefectRecipeSnapshot recipe = DefectRecipeSnapshot.Create(
                frameId,
                4,
                null,
                [DefectRecipeSamples.Edit(DefectEditKind.Brush)]);
            bool seeded;
            using (CatalogSession session = CatalogSession.Open(roots).Session!)
            {
                // 기존 사진에 결함 편집을 더하는 순서입니다: 카탈로그 → sidecar+선언.
                seeded = session.Write(Catalog(record)).IsSuccess;
                JsonObject declared = (JsonObject)record.DeepClone();
                declared["hasDefectEdits"] = true;
                DefectRecipeCatalogWriteResult written =
                    session.WriteDefectRecipeAndCatalog(recipe, Catalog(declared));
                seeded &= written.IsSuccess;
                Check(seeded, $"maintenance_{name}_seed",
                    () => $"{written.Sidecar.Error} {written.CatalogError}");
            }
            if (seeded)
            {
                test(roots, frameId);
            }
        }
        finally
        {
            try
            {
                if (Directory.Exists(isolatedBase) &&
                    StoragePathPolicy.IsLexicallyContained(parent, isolatedBase))
                {
                    Directory.Delete(isolatedBase, recursive: true);
                }
            }
            catch (IOException)
            {
            }
        }
    }

    private static CatalogSnapshot Catalog(JsonObject record) => new(
        null,
        new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
        {
            [CatalogEntityTable.Frames] =
                [new CatalogEntityRow(record["id"]!.GetValue<string>(), record)],
        });
}
