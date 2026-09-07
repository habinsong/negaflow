using System.Text.Json;
using System.Text.Json.Nodes;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using static Negaflow.Shell.UnitTests.TestAssert;
using static Negaflow.Shell.UnitTests.TestFrameFactory;

namespace Negaflow.Shell.UnitTests;

internal static class InfraredSessionLifecycleTests
{
    public static void Run()
    {
        string parent = Path.Combine(AppContext.BaseDirectory, "infrared-session-lifecycle-tests");
        string isolatedBase = Path.Combine(parent, $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;
        Guid frameId = Guid.Parse("5d3bb352-cbeb-43da-aeb0-a4639d4ebc1d");
        string frameIdText = frameId.ToString("D");
        string sourcePath = Path.Combine(isolatedBase, "visible.tif");
        string infraredPath = Path.Combine(isolatedBase, "infrared.tif");
        try
        {
            Directory.CreateDirectory(isolatedBase);
            File.WriteAllBytes(sourcePath, [1, 3, 5, 7]);
            File.WriteAllBytes(infraredPath, [2, 4, 6, 8]);
            Check(DefectSourceIdentityReader.TryRead(sourcePath, out DefectSourceIdentity identity),
                "infrared_session_source_identity");

            DefectEditItem region = RegionItem();
            DefectRecipeSnapshot recipe = DefectRecipeSnapshot.Create(
                frameId,
                recipeRevision: 1,
                identity,
                [region, InfraredItem()]);
            JsonObject plain = FrameRecord(frameIdText, "visible.tif", exposure: 0.0);
            plain[LibraryFrameReader.SourcePathName] = sourcePath;
            plain[LibraryFrameReader.InfraredPathName] = infraredPath;
            JsonObject declared = plain.DeepClone().AsObject();
            declared["hasDefectEdits"] = true;
            JsonObject reviewed = DefectReviewTrackingCodec.Apply(
                declared,
                new DefectReviewMarkRecord(
                    recipe.RecipeRevision,
                    recipe.RecipeSha256,
                    identity.Sha256)).FrameRecord!;
            using (CatalogSession seed = CatalogSession.Open(roots).Session!)
            {
                Check(seed.Write(Catalog(plain)).IsSuccess,
                    "infrared_session_seed_catalog");
                Check(seed.WriteDefectRecipeAndCatalog(recipe, Catalog(declared)).IsSuccess,
                    "infrared_session_seed_mixed_recipe");
                Check(seed.Write(Catalog(reviewed)).IsSuccess,
                    "infrared_session_seed_review");
            }

            using (LibraryDocument document = LibraryDocument.Open(roots).Document!)
            {
                LibraryFrameSnapshot frame = document.Frames.Single();
                Check(frame.DefectRecipe is { RecipeRevision: 1 } &&
                      frame.DefectRecipeRevision == 1,
                    "infrared_session_open_restores_previous_session_recipe");
                Check(frame.InfraredPath == infraredPath &&
                      !InfraredCleanPolicy.ShouldRun(frame, alreadyAttempted: false),
                    "infrared_session_open_does_not_repeat_restored_ir_detection");

                JsonObject record = document.FrameRecord(frameIdText)!;
                using JsonDocument recordJson = JsonDocument.Parse(record.ToJsonString());
                Check(DefectReviewTrackingCodec.Read(recordJson.RootElement) is not null,
                    "infrared_session_open_restores_review_identity");

                DefectRecipeSnapshot revisionTwo = DefectRecipeSnapshot.Create(
                    frameId,
                    recipeRevision: 2,
                    identity,
                    [region]);
                Check(document.WriteDefectRecipe(frameIdText, revisionTwo).IsSuccess,
                    "infrared_session_open_preserves_next_revision");
            }

            using LibraryDocument reopened = LibraryDocument.Open(roots).Document!;
            Check(reopened.Frames.Single() is
                  { DefectRecipe: { RecipeRevision: 2 }, DefectRecipeRevision: 2 },
                "infrared_session_next_open_restores_new_session_recipe");

            VerifyGammaKeepsDefectsAndInfrared(reopened, frameIdText, infraredPath, identity);
        }
        finally
        {
            if (Directory.Exists(isolatedBase) &&
                StoragePathPolicy.IsLexicallyContained(parent, isolatedBase))
            {
                Directory.Delete(isolatedBase, recursive: true);
            }
        }
    }

    /// <summary>
    /// 입력 감마를 바꿔도 <b>결함 recipe 와 IR 은 그대로</b>여야 합니다(W46·W47·W77).
    /// </summary>
    /// <remarks>
    /// <para>
    /// 감마는 원본을 <b>어떻게 읽을지</b>를 정할 뿐 원본 파일을 바꾸지 않습니다. 그런데
    /// 감마 편집이 결함 recipe 를 무르면 사용자가 찍어 둔 먼지·긁힘이 통째로 사라지고,
    /// 다시 칠하는 것 말고는 되돌릴 길이 없습니다. 반대로 recipe 를 들고 있으면서
    /// <b>원본 신원</b>까지 새로 쓰면 다음 굽기가 엉뚱한 화소에 패치를 붙입니다.
    /// </para>
    /// <para>
    /// IR 경로도 같습니다 — IR 파일은 RGB 와 별개로 스캔한 것이라 RGB 의 감마 해석이
    /// 바뀌었다고 다시 잡을 이유가 없습니다.
    /// </para>
    /// <para>
    /// 함께 확인하는 것: 감마 편집이 잰 base 는 무릅니다(<c>DevelopInputEditor.CreateEdit</c>).
    /// 그것은 새 해석에서 base 를 다시 재야 하기 때문이며, 결함과는 다른 이야기입니다.
    /// </para>
    /// </remarks>
    private static void VerifyGammaKeepsDefectsAndInfrared(
        LibraryDocument document,
        string frameIdText,
        string infraredPath,
        DefectSourceIdentity identity)
    {
        LibraryFrameSnapshot before = document.Frames.Single();
        Check(before.DefectRecipe is not null, "gamma_defects_start_with_a_recipe");
        int itemsBefore = before.DefectRecipe!.Items.Count;
        ulong revisionBefore = before.DefectRecipeRevision;

        foreach (InputGammaInterpretation gamma in new[]
        {
            InputGammaInterpretation.Power(1.8),
            InputGammaInterpretation.Power(3.0),
            InputGammaInterpretation.Automatic,
        })
        {
            LibraryFrameSnapshot frame = document.Frames.Single();
            Check(
                document.Edit(frameIdText, DevelopInputEditor.CreateEdit(frame, gamma)) ==
                    LibraryFrameError.None,
                $"gamma_defects_edit_{gamma}");

            LibraryFrameSnapshot after = document.Frames.Single();
            Check(after.InputGamma == gamma, $"gamma_defects_applies_{gamma}",
                () => after.InputGamma.ToString());
            Check(after.DefectRecipe is not null, $"gamma_defects_recipe_survives_{gamma}");
            Check(after.DefectRecipe!.Items.Count == itemsBefore,
                $"gamma_defects_item_count_survives_{gamma}",
                () => after.DefectRecipe!.Items.Count.ToString());
            Check(after.DefectRecipeRevision == revisionBefore,
                $"gamma_defects_revision_is_not_bumped_{gamma}",
                () => after.DefectRecipeRevision.ToString());
            // **원본 신원은 그대로입니다** - 감마는 파일을 바꾸지 않습니다.
            Check(after.DefectRecipe!.SourceIdentity?.Sha256 == identity.Sha256 &&
                  after.DefectRecipe!.SourceIdentity?.ByteCount == identity.ByteCount,
                $"gamma_defects_keep_the_source_identity_{gamma}");
            Check(after.InfraredPath == infraredPath, $"gamma_keeps_the_infrared_path_{gamma}",
                () => after.InfraredPath ?? "null");
            // 잰 base 는 무릅니다 - 새 해석에서 다시 재야 합니다.
            Check(after.ManualBase is null && after.Base.Mode != BaseEstimationMode.Manual,
                $"gamma_still_remeasures_the_base_{gamma}");
        }
    }

    private static DefectEditItem RegionItem()
    {
        byte[] mask = new byte[16];
        mask[5] = 255;
        return GrainMendRegionEdit.From(
            mask,
            4,
            4,
            20,
            10,
            0,
            0,
            20,
            10,
            1,
            automatic: false)!;
    }

    private static DefectEditItem InfraredItem()
    {
        byte[] mask = new byte[4 * 4 * 4];
        mask[0] = mask[1] = mask[2] = mask[3] = 255;
        return new DefectEditItem(
            Guid.NewGuid(),
            DefectEditKind.Infrared,
            Enabled: true,
            Strength: 1.0,
            new DefectEditLabel(DefectEditLabelKind.Infrared, 1),
            new DefectEditSummary(
                DefectEditSummaryKind.ClassBreakdown,
                new DefectClassBreakdown(
                    [new DefectClassCount(DefectClassification.Dust, 1)],
                    1.0)),
            new DefectSize(4.0, 4.0),
            [])
        {
            Clusters =
            [
                new DefectCluster(
                    new DefectRect(0.0, 0.0, 4.0, 4.0),
                    new DefectMask(false, mask),
                    4,
                    4),
            ],
        };
    }

    private static CatalogSnapshot Catalog(JsonObject record) => new(
        null,
        new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
        {
            [CatalogEntityTable.Frames] =
                [new CatalogEntityRow(record["id"]!.GetValue<string>(), record)],
        });
}
