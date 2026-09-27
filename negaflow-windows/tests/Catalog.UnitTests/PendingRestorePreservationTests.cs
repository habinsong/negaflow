using System.Text.Json.Nodes;
using static Negaflow.Catalog.UnitTests.CatalogTestAssert;

namespace Negaflow.Catalog.UnitTests;

/// <summary>
/// 예약 복원이 지금 파일로 검증된 안전 백업을 못 만들 때입니다. macOS
/// <c>LibraryPendingRestoreStore.preserveCurrentState</c> 처럼 원본 그대로 보관하고 진행해야
/// 합니다 — 멈추면 되돌리려는 바로 그 상황(결함 기록이 사라짐, 카탈로그 파일이 사라짐)에서
/// 라이브러리가 차단 화면에 갇힙니다.
/// </summary>
internal static class PendingRestorePreservationTests
{
    public static void Run(StorageRootSet parentRoots)
    {
        Verify(parentRoots, "declared-sidecar-missing", (roots, frameId) =>
            File.Delete(Path.Combine(roots.DefectRecipeRoot, $"{frameId:D}.json")));
        // 카탈로그와 그 이전 판 사본이 모두 없고 결함 기록만 남은 경우입니다. 사본이 남아 있으면
        // 커밋이 중단된 자리로 보고 Windows 롤백 규칙이 따로 막습니다.
        Verify(parentRoots, "catalog-missing", (roots, _) =>
        {
            File.Delete(roots.CatalogPath);
            File.Delete(roots.CatalogBackupPath);
        });
        // 카탈로그만 사라지고 커밋이 남긴 직전 판 사본은 남은 경우입니다(동기화 도구가 지웠거나
        // 예전 "새 라이브러리로 시작" 이 주 파일만 지우고 멈춘 자리). 사본도 보관하고 진행합니다.
        Verify(parentRoots, "catalog-missing-previous-copy-left", (roots, _) =>
        {
            Check(File.Exists(roots.CatalogBackupPath), "preservation_previous_copy_exists");
            File.Delete(roots.CatalogPath);
        });
        // 복구 화면에서 고르는 경우입니다. 이미 막힌 라이브러리라 세션을 열 수 없으므로 예약은
        // 카탈로그를 열지 않고 해야 합니다(macOS `LibraryPendingRestoreStore.schedule`).
        Verify(parentRoots, "scheduled-while-blocked", (roots, frameId) =>
            File.Delete(Path.Combine(roots.DefectRecipeRoot, $"{frameId:D}.json")),
            scheduleWhileBlocked: true);
    }

    private static void Verify(
        StorageRootSet parentRoots,
        string name,
        Action<StorageRootSet, Guid> breakCurrentState,
        bool scheduleWhileBlocked = false)
    {
        StorageRootSet roots = StorageRootResolver.ResolveForTests(Path.Combine(
            parentRoots.LocalApplicationDataRoot,
            "pending-restore-preservation-" + name)).Roots!;
        Guid frameId = Guid.Parse("5c1f0a8e-2b6d-4f7a-9e3c-1d2a4b6c8e0f");
        DefectRecipeSnapshot recipe = DefectRecipeSnapshot.Create(
            frameId,
            2,
            null,
            DefectTestFixture.DefectRecipeItems());
        string generationId;
        using (CatalogSession session = CatalogSession.Open(roots).Session!)
        {
            Check(session.ReadOrCreate().IsSuccess, $"preservation_{name}_create");
            Check(session.Write(Snapshot(frameId, declares: false)).IsSuccess,
                $"preservation_{name}_seed");
            Check(session.WriteDefectRecipeAndCatalog(recipe, Snapshot(frameId, declares: true))
                    .IsSuccess,
                $"preservation_{name}_seed_recipe");
            CatalogBackupCreateResult backup = session.CreateBackupForTesting(
                new DateTimeOffset(2026, 9, 27, 7, 0, 0, TimeSpan.Zero));
            Check(backup.IsSuccess, $"preservation_{name}_backup");
            generationId = Path.GetFileName(backup.GenerationPath ?? string.Empty);
            if (!scheduleWhileBlocked)
            {
                Check(session.ScheduleRestore(generationId).IsSuccess,
                    $"preservation_{name}_schedule");
            }
        }

        breakCurrentState(roots, frameId);
        if (scheduleWhileBlocked)
        {
            CatalogSessionOpenResult blocked = CatalogSession.Open(roots);
            blocked.Session?.Dispose();
            Check(!blocked.IsSuccess, $"preservation_{name}_is_blocked");
            CatalogPendingRestoreScheduleResult scheduled =
                CatalogRecovery.ScheduleRestore(roots, generationId);
            Check(scheduled.IsSuccess, $"preservation_{name}_schedule",
                () => scheduled.Error.ToString());
        }

        CatalogSessionOpenResult reopened = CatalogSession.Open(roots);
        using (CatalogSession? session = reopened.Session)
        {
            Check(reopened.IsSuccess, $"preservation_{name}_restore_applies",
                () => $"{reopened.Error} {reopened.PendingRestoreError}");
            Check(CatalogRecovery.PendingRestoreGenerationId(roots) is null,
                $"preservation_{name}_marker_consumed");
            Check(session?.ReadDefectRecipe(frameId).Snapshot?.RecipeSha256 == recipe.RecipeSha256,
                $"preservation_{name}_recipe_restored");
        }
        Check(Directory.EnumerateFileSystemEntries(roots.LibraryRoot, "*.corrupt-*").Any(),
            $"preservation_{name}_current_state_preserved");
    }

    private static CatalogSnapshot Snapshot(Guid frameId, bool declares)
    {
        JsonObject payload = new() { ["id"] = frameId.ToString("D"), ["label"] = "frame" };
        if (declares)
        {
            payload["hasDefectEdits"] = true;
        }
        return new CatalogSnapshot(null, new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
        {
            [CatalogEntityTable.Frames] = [new CatalogEntityRow(frameId.ToString("D"), payload)],
        });
    }
}
