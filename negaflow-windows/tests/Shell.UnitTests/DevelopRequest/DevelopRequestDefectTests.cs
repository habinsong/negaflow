using System.Text.Json;
using System.Text.Json.Nodes;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Library;
using Negaflow.Shell.Print;
using Negaflow.Shell.Shortcuts;
using static Negaflow.Shell.UnitTests.DevelopTestResults;
using static Negaflow.Shell.UnitTests.TestAssert;
using static Negaflow.Shell.UnitTests.TestFrameFactory;

namespace Negaflow.Shell.UnitTests;

internal static class DevelopRequestDefectTests
{
    public static void Run()
    {
        const string destination = @"C:\exports\IMG_0001.png";

        Guid defectFrameId = Guid.Parse("92e43a49-e80a-4d33-af27-1d5b1fe947e3");
        byte[] defectMask = Enumerable.Range(0, 16)
            .Select(value => (byte)value)
            .ToArray();
        DefectEditItem regionEdit = new(
            Guid.Parse("ff9a1c0e-03b1-427f-a19a-c13679147037"),
            DefectEditKind.Region,
            Enabled: true,
            Strength: 0.6,
            new DefectEditLabel(DefectEditLabelKind.Guided, 1),
            new DefectEditSummary(
                DefectEditSummaryKind.ClassBreakdown,
                new DefectClassBreakdown(
                    [new DefectClassCount(DefectClassification.Dust, 1)],
                    0.9)),
            new DefectSize(100, 80),
            [])
        {
            RegionMask = new DefectMask(false, defectMask),
            RegionRoi = new DefectRect(12, 34, 2, 2),
            RegionWidth = 2,
            RegionHeight = 2,
        };
        DefectRecipeSnapshot defectRecipe = DefectRecipeSnapshot.Create(
            defectFrameId,
            recipeRevision: 3,
            new DefectSourceIdentity(123, new string('d', 64)),
            [regionEdit]);
        DevelopRequestResult defectRequest = DevelopRequestFactory.Create(
            Frame(new ManualBaseRgb(0.21, 0.22, 0.23)) with
            {
                DefectRecipe = defectRecipe,
            },
            destination);
        Check(defectRequest.IsSuccess &&
              defectRequest.Request?.DefectRegions.Count == 1 &&
              defectRequest.Request.DefectRegions[0].RoiX == 12 &&
              defectRequest.Request.DefectRegions[0].RoiY == 34 &&
              defectRequest.Request.DefectRegions[0].MaskStrideBytes == 8 &&
              defectRequest.Request.DefectRegions[0].Strength == 0.6 &&
              defectRequest.Request.DefectRegions[0].Mask.Span.SequenceEqual(defectMask) &&
              defectRequest.Request.DefectEditOrder.SequenceEqual(
              [
                  new DevelopDefectRecipeEditRef(DevelopDefectEditKind.Region, 0),
              ]) &&
              // 내용 해시가 꺼져 있으면(기본값) sha 자리는 0 입니다 — 네이티브가 그것을
              // "바이트 수만 확인" 으로 읽습니다. ABI 가 identity 자체는 요구하므로 자리는
              // 그대로 채워 보냅니다.
              defectRequest.Request.DefectSourceIdentity ==
                  new DevelopDefectSourceIdentity(123, new string(char.Parse("0"), 64)) &&
              defectRequest.Request.DefectRecipeSha256 == defectRecipe.RecipeSha256,
            "develop_request_projects_persisted_region_defect");

        byte[] infraredCoreRgba = new byte[4 * 4 * 4];
        infraredCoreRgba[5 * 4] = 255;
        infraredCoreRgba[6 * 4] = 128;
        byte[] infraredAttenuation = new byte[4 * 4 * 2];
        infraredAttenuation[2 * 5] = 0x00;
        infraredAttenuation[2 * 5 + 1] = 0x80;
        DefectEditItem infraredEdit = new(
            Guid.Parse("f56375c4-43f8-48ba-8daf-f2ae95d06d97"),
            DefectEditKind.Infrared,
            Enabled: true,
            Strength: 0.8,
            new DefectEditLabel(DefectEditLabelKind.Infrared, 1),
            new DefectEditSummary(
                DefectEditSummaryKind.ClassBreakdown,
                new DefectClassBreakdown([], 0.9)),
            new DefectSize(100, 80),
            [])
        {
            Clusters =
            [
                new DefectCluster(
                    new DefectRect(24, 30, 4, 4),
                    new DefectMask(false, infraredCoreRgba),
                    4,
                    4,
                    new DefectMask(false, infraredAttenuation)),
            ],
        };

        DefectEditItem cloneEdit = new(
            Guid.Parse("4a72f873-a8b3-44fc-a427-e57e85d7bb01"),
            DefectEditKind.Clone,
            Enabled: true,
            Strength: 0.7,
            new DefectEditLabel(DefectEditLabelKind.Clone, 12),
            new DefectEditSummary(DefectEditSummaryKind.Clone),
            new DefectSize(100, 80),
            [])
        {
            CloneStrokes =
            [
                new DefectCloneStroke(
                    [new DefectPoint(0.4, 0.5), new DefectPoint(0.45, 0.55)],
                    -0.1,
                    0.2,
                    12,
                    0.8),
            ],
        };
        DefectEditItem secondRegionEdit = regionEdit with
        {
            Id = Guid.Parse("60db3ee5-c25e-4182-840b-8a7196190d61"),
            RegionRoi = new DefectRect(20, 30, 2, 2),
        };
        DefectRecipeSnapshot orderedDefectRecipe = DefectRecipeSnapshot.Create(
            defectFrameId,
            recipeRevision: 4,
            new DefectSourceIdentity(123, new string('d', 64)),
            [regionEdit, infraredEdit, cloneEdit, secondRegionEdit]);
        DevelopRequestResult orderedDefectRequest = DevelopRequestFactory.Create(
            Frame(new ManualBaseRgb(0.21, 0.22, 0.23)) with
            {
                DefectRecipe = orderedDefectRecipe,
            },
            destination);
        Check(
            orderedDefectRequest.IsSuccess &&
            orderedDefectRequest.Request?.DefectRegions.Count == 2 &&
            orderedDefectRequest.Request.DefectInfrared.Count == 1 &&
            orderedDefectRequest.Request.DefectInfrared[0].Clusters.Count == 1 &&
            orderedDefectRequest.Request.DefectInfrared[0].Clusters[0].RoiX == 24 &&
            orderedDefectRequest.Request.DefectInfrared[0].Clusters[0]
                .CoreMaskStrideBytes == 4 &&
            orderedDefectRequest.Request.DefectInfrared[0].Clusters[0]
                .CoreMask.Span[5] == 255 &&
            orderedDefectRequest.Request.DefectInfrared[0].Clusters[0]
                .CoreMask.Span[6] == 128 &&
            orderedDefectRequest.Request.DefectInfrared[0].Clusters[0]
                .AttenuationStrideBytes == 8 &&
            orderedDefectRequest.Request.DefectInfrared[0].Clusters[0]
                .AttenuationR16?.Span[
                2 * 5 + 1] == 0x80 &&
            orderedDefectRequest.Request.DefectClones.Count == 1 &&
            orderedDefectRequest.Request.DefectClones[0].Strength == 0.7 &&
            orderedDefectRequest.Request.DefectClones[0].Strokes[0].OffsetX == -0.1 &&
            orderedDefectRequest.Request.DefectEditOrder.SequenceEqual(
            [
                new DevelopDefectRecipeEditRef(DevelopDefectEditKind.Region, 0),
                new DevelopDefectRecipeEditRef(DevelopDefectEditKind.Infrared, 0),
                new DevelopDefectRecipeEditRef(DevelopDefectEditKind.Clone, 0),
                new DevelopDefectRecipeEditRef(DevelopDefectEditKind.Region, 1),
            ]) &&
            orderedDefectRequest.Request.DefectRecipeSha256 ==
                orderedDefectRecipe.RecipeSha256 &&
            orderedDefectRequest.Request.DefectRecipeAppendPrefixEditCount == 3 &&
            orderedDefectRequest.Request.DefectRecipeAppendPrefixSha256 ==
                DefectRecipeSnapshot.Create(
                    defectFrameId,
                    recipeRevision: 3,
                    new DefectSourceIdentity(123, new string('d', 64)),
                    [regionEdit, infraredEdit, cloneEdit]).RecipeSha256,
            "develop_request_preserves_interleaved_region_infrared_clone_order");

        DefectEditItem legacyInfraredEdit = infraredEdit with
        {
            Clusters =
            [
                infraredEdit.Clusters![0] with { AttenuationR16 = null },
            ],
        };
        DefectRecipeSnapshot legacyInfraredRecipe = DefectRecipeSnapshot.Create(
            defectFrameId,
            recipeRevision: 5,
            new DefectSourceIdentity(123, new string('d', 64)),
            [legacyInfraredEdit]);
        Check(legacyInfraredRecipe.Items[0].Clusters![0].AttenuationR16 is null,
            "defect_recipe_keeps_legacy_attenuation_absent");
        DevelopRequestResult legacyInfraredRequest = DevelopRequestFactory.Create(
            Frame(new ManualBaseRgb(0.21, 0.22, 0.23)) with
            {
                DefectRecipe = legacyInfraredRecipe,
            },
            destination);
        Check(legacyInfraredRequest.IsSuccess,
            "develop_request_accepts_legacy_mask_only_infrared");
        Check(legacyInfraredRequest.Request?.DefectInfrared.Count == 1,
            "develop_request_keeps_legacy_infrared_separate");
        Check(legacyInfraredRequest.Request is { } legacyNativeRequest &&
              legacyNativeRequest.DefectInfrared[0].Clusters[0]
                  .AttenuationR16 is null,
            "develop_request_preserves_missing_legacy_attenuation");
        Check(legacyInfraredRequest.Request?.DefectInfrared[0].Clusters[0]
                  .AttenuationStrideBytes == 0,
            "develop_request_zeros_missing_legacy_attenuation_stride");
        Check(legacyInfraredRequest.Request?.DefectEditOrder.SequenceEqual(
              [
                  new DevelopDefectRecipeEditRef(DevelopDefectEditKind.Infrared, 0),
              ]) == true,
            "develop_request_orders_legacy_infrared_separately");

        DefectEditItem corruptInfraredEdit = infraredEdit with
        {
            Clusters =
            [
                infraredEdit.Clusters![0] with
                {
                    AttenuationR16 = new DefectMask(true, [1, 2, 3]),
                },
            ],
        };
        DefectRecipeSnapshot corruptInfraredRecipe = DefectRecipeSnapshot.Create(
            defectFrameId,
            recipeRevision: 6,
            new DefectSourceIdentity(123, new string('d', 64)),
            [corruptInfraredEdit]);
        Check(DevelopRequestFactory.Create(
                Frame(new ManualBaseRgb(0.21, 0.22, 0.23)) with
                {
                    DefectRecipe = corruptInfraredRecipe,
                },
                destination).Refusal == DevelopRequestRefusal.InvalidDefectRecipe,
            "develop_request_rejects_corrupt_infrared_attenuation");

        DefectRecipeSnapshot unboundRegionRecipe = DefectRecipeSnapshot.Create(
            defectFrameId,
            recipeRevision: 4,
            sourceIdentity: null,
            [regionEdit]);
        Check(DevelopRequestFactory.Create(
                Frame(new ManualBaseRgb(0.21, 0.22, 0.23)) with
                {
                    DefectRecipe = unboundRegionRecipe,
                },
                destination).Refusal == DevelopRequestRefusal.InvalidDefectRecipe,
            "develop_request_rejects_unbound_region_defect_recipe");

        DefectEditItem brushEdit = new(
            Guid.Parse("43309589-b878-48d5-969e-52d00683a2f4"),
            DefectEditKind.Brush,
            Enabled: true,
            Strength: 1,
            new DefectEditLabel(DefectEditLabelKind.Brush, 1),
            new DefectEditSummary(DefectEditSummaryKind.Brush),
            new DefectSize(100, 80),
            [])
        {
            Strokes =
            [
                new DefectStroke([new DefectPoint(0.2, 0.3)], 0.01),
            ],
        };
        DefectRecipeSnapshot brushDefectRecipe = DefectRecipeSnapshot.Create(
            defectFrameId,
            recipeRevision: 5,
            new DefectSourceIdentity(123, new string('d', 64)),
            [regionEdit, brushEdit]);
        DevelopRequestResult brushDefectRequest = DevelopRequestFactory.Create(
            Frame(new ManualBaseRgb(0.21, 0.22, 0.23)) with
            {
                DefectRecipe = brushDefectRecipe,
            },
            destination);
        Check(
            brushDefectRequest.IsSuccess &&
            brushDefectRequest.Request?.DefectBrushes.Count == 1 &&
            brushDefectRequest.Request.DefectBrushes[0].Strength == 1 &&
            brushDefectRequest.Request.DefectBrushes[0].Strokes[0].Thickness == 0.01 &&
            brushDefectRequest.Request.DefectBrushes[0].Strokes[0].Points.SequenceEqual(
            [
                new DevelopDefectBrushPoint(0.2, 0.3),
            ]) &&
            brushDefectRequest.Request.DefectEditOrder.SequenceEqual(
            [
                new DevelopDefectRecipeEditRef(DevelopDefectEditKind.Region, 0),
                new DevelopDefectRecipeEditRef(DevelopDefectEditKind.Brush, 0),
            ]) &&
            brushDefectRequest.Request.DefectSourceIdentity ==
                new DevelopDefectSourceIdentity(123, new string(char.Parse("0"), 64)),
            "develop_request_projects_brush_and_preserves_order");

        // 설정 `이미지 내용 해시` 를 켜면 **원본 sha 가 실려야** 합니다. 이것이 빠지면
        // 네이티브가 내용 검증을 영영 건너뛰고, 설정이 다시 죽은 값이 됩니다.
        // 끄면 sha 자리가 0 이고 네이티브는 바이트 수만 확인합니다 — 그래야 결함 편집이
        // 걸린 사진의 슬라이더가 렌더마다 원본 전체를 다시 읽지 않습니다.
        try
        {
            DevelopRequestFactory.VerifyDefectSourceContent = true;
            Check(
                DevelopRequestFactory.Create(
                    Frame(new ManualBaseRgb(0.21, 0.22, 0.23)) with
                    {
                        DefectRecipe = defectRecipe,
                    },
                    destination).Request?.DefectSourceIdentity ==
                        new DevelopDefectSourceIdentity(123, new string('d', 64)),
                "develop_request_carries_source_sha_when_content_hash_is_on");
        }
        finally
        {
            DevelopRequestFactory.VerifyDefectSourceContent = false;
        }

        DefectEditItem invalidBrushEdit = brushEdit with
        {
            Strokes =
            [
                new DefectStroke([new DefectPoint(2, 0.3)], 0.01),
            ],
        };
        DefectRecipeSnapshot invalidBrushRecipe = DefectRecipeSnapshot.Create(
            defectFrameId,
            recipeRevision: 6,
            new DefectSourceIdentity(123, new string('d', 64)),
            [invalidBrushEdit]);
        Check(
            DevelopRequestFactory.Create(
                Frame(new ManualBaseRgb(0.21, 0.22, 0.23)) with
                {
                    DefectRecipe = invalidBrushRecipe,
                },
                destination).Refusal == DevelopRequestRefusal.InvalidDefectRecipe,
            "develop_request_rejects_out_of_range_brush_geometry");

        VerifyInfraredProjectionBoundary(
            defectFrameId, infraredEdit, destination, clusterCount: 4_096);
        VerifyInfraredProjectionBoundary(
            defectFrameId, infraredEdit, destination, clusterCount: 4_097);
    }

    private static void VerifyInfraredProjectionBoundary(
        Guid frameId,
        DefectEditItem infraredEdit,
        string destination,
        int clusterCount)
    {
        DefectEditItem boundaryEdit = infraredEdit with
        {
            Clusters = Enumerable.Repeat(
                infraredEdit.Clusters!.Single(), clusterCount).ToArray(),
        };
        DefectRecipeSnapshot recipe = DefectRecipeSnapshot.Create(
            frameId,
            recipeRevision: checked((ulong)clusterCount),
            new DefectSourceIdentity(123, new string('d', 64)),
            [boundaryEdit]);
        DevelopRequestResult result = DevelopRequestFactory.Create(
            Frame(new ManualBaseRgb(0.21, 0.22, 0.23)) with
            {
                DefectRecipe = recipe,
            },
            destination);
        Check(
            result.IsSuccess &&
            result.Request?.DefectInfrared.Count == 1 &&
            result.Request.DefectInfrared[0].Clusters.Count == clusterCount &&
            result.Request.DefectEditOrder.SequenceEqual(
            [
                new DevelopDefectRecipeEditRef(DevelopDefectEditKind.Infrared, 0),
            ]),
            $"develop_request_projects_{clusterCount}_infrared_clusters_as_one_item");
    }
}
