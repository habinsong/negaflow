using System.Text.Json.Nodes;
using static Negaflow.Catalog.UnitTests.CatalogTestAssert;

namespace Negaflow.Catalog.UnitTests;

/// <summary>
/// 결함 편집을 선언하지 않은 사진 자리에 남은 못 읽는 기록입니다. 예전에는 카탈로그가 참조하지도 않는
/// 이 파일 하나로 라이브러리 전체가 "결함 보정 레시피가 불완전하다" 며 막혔습니다. macOS 는 알 수
/// 없는 파일을 두고 엽니다.
/// </summary>
internal static class DefectUndeclaredSidecarTests
{
    public static void Run(StorageRootSet roots)
    {
        Guid frameId = Guid.Parse("5b0d6f1e-8a0c-4f5e-9d7b-2a1c3e4f5a6b");
        StorageRootSet garbageRoots = StorageRootResolver.ResolveForTests(Path.Combine(
            roots.LocalApplicationDataRoot,
            $"defect-undeclared-garbage-{Guid.NewGuid():N}")).Roots!;
        CatalogSnapshot catalog = new(
            null,
            new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
            {
                [CatalogEntityTable.Frames] =
                [
                    new CatalogEntityRow(frameId.ToString("D"), new JsonObject { ["hasDefectEdits"] = false }),
                ],
            });
        Check(SqliteCatalogStore.Write(catalog, garbageRoots.CatalogPath).IsSuccess,
            "defect_undeclared_garbage_catalog_seed");
        Directory.CreateDirectory(garbageRoots.DefectRecipeRoot);
        string garbagePath = DefectSidecarStore.PathFor(garbageRoots, frameId);
        File.WriteAllText(garbagePath, "{ broken");

        // 쓰레기는 보관 사본을 남기고 치웁니다 — 남겨 두면 그 사진의 새 편집이 거부됩니다.
        CatalogSessionOpenResult opened = CatalogSession.Open(garbageRoots);
        opened.Session?.Dispose();
        Check(opened.IsSuccess && !File.Exists(garbagePath) &&
              Directory.EnumerateDirectories(garbageRoots.LibraryRoot, "defects.corrupt-*").Any(),
            "defect_undeclared_garbage_is_sidelined_without_blocking_the_open",
            () => $"{opened.Error}/{opened.DefectSidecarError} exists={File.Exists(garbagePath)}");
    }
}
