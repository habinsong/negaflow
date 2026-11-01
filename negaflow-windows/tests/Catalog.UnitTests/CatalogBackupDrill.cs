namespace Negaflow.Catalog.UnitTests;

/// <summary>
/// 라이브러리 사본으로 백업 세대 생성 → 예약 복원 → 적용을 앱과 같은 함수로 돌립니다.
/// <c>--backup-drill &lt;root&gt;</c> 로만 돌고, 결과 대조는 사본 바깥의 스크립트가 합니다.
/// </summary>
internal static class CatalogBackupDrill
{
    internal const string Argument = "--backup-drill";

    internal static int Run(string root)
    {
        StorageRootResolutionResult resolved = StorageRootResolver.ResolveForTests(root);
        if (!resolved.IsSuccess || resolved.Roots is not { } roots)
        {
            Console.WriteLine($"roots failed: {resolved.Error}");
            return 1;
        }
        DateTimeOffset now = DateTimeOffset.UtcNow;
        CatalogBackupCreateResult created = CatalogBackupStore.Create(
            roots,
            now,
            CatalogBackupStore.DefaultRetentionCount);
        Console.WriteLine(
            $"create success={created.IsSuccess} error={created.Error} " +
            $"seq={created.Sequence} pruneFailed={created.RetentionPruneFailed}");
        if (!created.IsSuccess || created.GenerationPath is null)
        {
            return 1;
        }
        foreach (CatalogBackupGeneration generation in CatalogBackupInspector.Enumerate(roots))
        {
            Console.WriteLine(
                $"generation {generation.Id} {generation.State} " +
                $"frames={generation.FrameCount} recipes={generation.DefectRecipeCount}");
        }

        CatalogPendingRestoreScheduleResult scheduled = CatalogPendingRestoreStore.Schedule(
            roots,
            Path.GetFileName(created.GenerationPath),
            now);
        Console.WriteLine($"schedule success={scheduled.IsSuccess} error={scheduled.Error}");
        if (!scheduled.IsSuccess)
        {
            return 1;
        }

        // 복원이 실제로 적용됐는지 가리려고 결함 기록 다섯 개를 지웁니다. 세대에서 돌아와야 합니다.
        foreach (string file in Directory.EnumerateFiles(roots.DefectRecipeRoot)
            .Order(StringComparer.Ordinal)
            .Take(5))
        {
            File.Delete(file);
        }
        CatalogPendingRestoreApplicationResult applied =
            CatalogPendingRestoreStore.ApplyIfScheduled(roots, now.AddMinutes(1));
        Console.WriteLine(
            $"apply success={applied.IsSuccess} applied={applied.DidApplyRestore} error={applied.Error}");
        return applied.IsSuccess && applied.DidApplyRestore ? 0 : 1;
    }
}
