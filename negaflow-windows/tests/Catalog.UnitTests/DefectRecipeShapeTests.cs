using static Negaflow.Catalog.UnitTests.CatalogTestAssert;

namespace Negaflow.Catalog.UnitTests;

/// <summary>
/// 기록을 만들 때 마스크·적외선 감쇠 창의 크기를 봅니다. macOS 1.1.8
/// <c>DefectSidecarResourcePolicy.checkAttenuationShape</c> 와 같은 규칙입니다. 만들 때 압축부터 하면
/// 크기가 틀린 원본도 받아들이고, 읽을 때(압축을 풀어 정확한 크기인지 보는 자리)에서야 거부합니다 —
/// 쓰기가 받아들인 기록을 읽기가 거부하면 그 기록은 저장되지 않습니다.
/// </summary>
internal static class DefectRecipeShapeTests
{
    public static void Run(StorageRootSet parentRoots)
    {
        IReadOnlyList<DefectEditItem> items = DefectTestFixture.DefectRecipeItems();
        DefectEditItem infrared = items.Single(item => item.Kind == DefectEditKind.Infrared);
        DefectCluster cluster = infrared.Clusters![0];
        int pixels = cluster.Width * cluster.Height;

        Check(Rejected(infrared with
            {
                Clusters = [cluster with { AttenuationR16 = new DefectMask(false, new byte[(pixels * 2) - 2]) }],
            }),
            "defect_recipe_rejects_short_attenuation_at_creation");
        Check(Rejected(infrared with
            {
                Clusters = [cluster with { Mask = new DefectMask(false, new byte[(pixels * 4) - 1]) }],
            }),
            "defect_recipe_rejects_short_cluster_mask_at_creation");

        // 맞는 크기는 쓰고 그대로 다시 읽힙니다.
        StorageRootSet roots = StorageRootResolver.ResolveForTests(Path.Combine(
            parentRoots.LocalApplicationDataRoot,
            "defect-recipe-shape")).Roots!;
        Guid frameId = Guid.Parse("0b1e6c7d-3f52-4a8e-9d21-6c4f8a2b7e90");
        DefectRecipeSnapshot valid = DefectRecipeSnapshot.Create(
            frameId,
            1,
            null,
            [infrared with
            {
                Clusters = [cluster with { AttenuationR16 = new DefectMask(false, new byte[pixels * 2]) }],
            }]);
        Check(DefectSidecarStore.Write(roots, valid).Kind == DefectSidecarWriteKind.Written &&
              DefectSidecarStore.Read(roots, frameId).Snapshot?.RecipeSha256 == valid.RecipeSha256,
            "defect_recipe_valid_attenuation_round_trips");
    }

    private static bool Rejected(DefectEditItem item)
    {
        try
        {
            _ = DefectRecipeSnapshot.Create(Guid.NewGuid(), 1, null, [item]);
            return false;
        }
        catch (ArgumentException)
        {
            return true;
        }
    }
}
