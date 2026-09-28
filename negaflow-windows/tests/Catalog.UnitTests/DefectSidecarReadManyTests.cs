using System.Text;
using System.Text.Json.Nodes;
using static Negaflow.Catalog.UnitTests.CatalogTestAssert;
using static Negaflow.Catalog.UnitTests.DefectTestFixture;

namespace Negaflow.Catalog.UnitTests;

/// <summary>
/// 결함 기록을 여러 장 한꺼번에 읽는 길입니다. 켤 때 한 장씩 풀던 것을 나눠 풀게 했으므로, 결과와
/// 오류가 한 장씩 읽던 때와 같은 차례로 나오는지를 지킵니다.
/// </summary>
internal static class DefectSidecarReadManyTests
{
    public static void Run(StorageRootSet parentRoots)
    {
        StorageRootSet roots = StorageRootResolver.ResolveForTests(Path.Combine(
            parentRoots.LocalApplicationDataRoot,
            $"defect-read-many-{Guid.NewGuid():N}")).Roots!;
        Guid first = Guid.Parse("11a0c3d2-5b7e-4f61-9a8b-0c1d2e3f4a5b");
        Guid broken = Guid.Parse("22b1d4e3-6c8f-4072-ab9c-1d2e3f4a5b6c");
        Guid missing = Guid.Parse("33c2e5f4-7d90-4183-bcad-2e3f4a5b6c7d");
        Guid last = Guid.Parse("44d3f605-8ea1-4294-cdbe-3f4a5b6c7d8e");
        IReadOnlyList<DefectEditItem> items = DefectRecipeItems();
        foreach (Guid frameId in new[] { first, broken, last })
        {
            Check(DefectSidecarStore.Write(
                    roots,
                    DefectRecipeSnapshot.Create(frameId, recipeRevision: 1, sourceIdentity: null, items)).IsSuccess,
                "defect_read_many_seed");
        }
        File.WriteAllText(DefectSidecarStore.PathFor(roots, broken), "{ broken");

        DefectSidecarReadResult[] many = DefectSidecarStore.ReadMany(
            roots,
            [first, broken, missing, Guid.Empty, last]);
        Check(
            many.Length == 5 &&
            many[0].Snapshot is { } firstRead &&
            DefectSidecarStore.Read(roots, first).Snapshot is { } firstSingle &&
            DefectSidecarCodec.AreSameSnapshot(firstRead, firstSingle) &&
            many[1].Error == DefectSidecarError.InvalidContent &&
            many[2].Error == DefectSidecarError.NotFound &&
            many[3].Error == DefectSidecarError.InvalidFrameId &&
            many[4].Snapshot?.FrameId == last,
            "defect_read_many_keeps_order_and_each_error",
            () => string.Join(",", many.Select(result => result.Error)));

        // 먼저 선언된 사진의 오류가 먼저 나갑니다 - 뒤 사진의 선언이 틀려도 그렇습니다.
        Check(
            DefectSidecarCatalogHealth.ValidateDeclaredSidecars(roots, Declaring(first, broken, missing)) ==
                DefectSidecarError.InvalidContent &&
            DefectSidecarCatalogHealth.ValidateDeclaredSidecars(roots, Declaring(first, missing, broken)) ==
                DefectSidecarError.NotFound,
            "defect_validate_declared_reports_the_first_frame_error");
        Check(
            DefectSidecarCatalogHealth.ValidateDeclaredSidecars(roots, WithBadDeclaration(Declaring(missing, last))) ==
                DefectSidecarError.NotFound &&
            DefectSidecarCatalogHealth.ValidateDeclaredSidecars(roots, WithBadDeclaration(Declaring(first))) ==
                DefectSidecarError.InvalidContent,
            "defect_validate_declared_reads_files_before_a_later_bad_declaration");

        // 중복 키는 어느 깊이든 거절합니다(예전 JsonObject 도 예외로 거절했습니다).
        string text = Encoding.UTF8.GetString(DefectSidecarCodec.Serialize(
            DefectRecipeSnapshot.Create(first, recipeRevision: 1, sourceIdentity: null, items)));
        int nested = text.IndexOf("\"enabled\":", StringComparison.Ordinal);
        Check(
            DefectSidecarCodec.Decode(Encoding.UTF8.GetBytes(text), first).IsSuccess &&
            DefectSidecarCodec.Decode(
                Encoding.UTF8.GetBytes("{\"version\":2," + text[1..]),
                first).Error == DefectSidecarError.InvalidContent &&
            nested > 0 &&
            DefectSidecarCodec.Decode(
                Encoding.UTF8.GetBytes(text.Insert(nested, "\"enabled\":false,")),
                first).Error == DefectSidecarError.InvalidContent,
            "defect_sidecar_decode_rejects_duplicate_keys");
    }

    private static CatalogSnapshot Declaring(params Guid[] frameIds) => new(
        null,
        new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
        {
            [CatalogEntityTable.Frames] =
            [
                .. frameIds.Select(frameId => new CatalogEntityRow(
                    frameId.ToString("D"),
                    new JsonObject { ["hasDefectEdits"] = true })),
            ],
        });

    private static CatalogSnapshot WithBadDeclaration(CatalogSnapshot snapshot) => new(
        null,
        new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
        {
            [CatalogEntityTable.Frames] =
            [
                .. snapshot.Rows(CatalogEntityTable.Frames),
                new CatalogEntityRow(
                    Guid.Parse("55e40716-9fb2-43a5-8ecf-4a5b6c7d8e9f").ToString("D"),
                    new JsonObject { ["hasDefectEdits"] = "yes" }),
            ],
        });
}
