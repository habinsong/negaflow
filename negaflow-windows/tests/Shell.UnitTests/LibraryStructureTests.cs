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

internal static class LibraryStructureTests
{
    internal static void VerifyVirtualCopies(string parent)
    {
        StorageRootSet roots = StorageRootResolver.ResolveForTests(
            Path.Combine(parent, "virtual-copies")).Roots!;

        using (CatalogSession seed = CatalogSession.Open(roots).Session!)
        {
            Check(
                seed.Write(new CatalogSnapshot(
                    null,
                    new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
                    {
                        [CatalogEntityTable.Frames] =
                        [
                            new("frame-1", FrameRecord("frame-1", "IMG_0001.tif", 1.25, 1)),
                            new("frame-2", FrameRecord("frame-2", "IMG_0002.tif", 0.5, 2)),
                        ],
                    })).IsSuccess,
                "virtual_copy_seed");
        }

        string? firstCopy;
        using (LibraryDocument document = LibraryDocument.Open(roots).Document!)
        {
            Check(document.CreateVirtualCopy("missing") is null, "virtual_copy_unknown_id");
            firstCopy = document.CreateVirtualCopy("frame-1");
            if (firstCopy is null)
            {
                Check(false, "virtual_copy_create");
                return;
            }
            Check(true, "virtual_copy_create");

            // 사본은 원본 바로 뒤에 들어갑니다 — 목록에서 나란히 보여야 합니다.
            Check(
                string.Join(',', document.Frames.Select(frame => frame.Id)) ==
                    $"frame-1,{firstCopy},frame-2",
                "virtual_copy_sits_next_to_its_original");

            LibraryFrameSnapshot copy = document.Frames[1];
            Check(copy.SourcePath == @"C:\scans\IMG_0001.tif", "virtual_copy_shares_the_source");
            Check(copy.Tone.Exposure == 1.25, "virtual_copy_inherits_the_recipe");
            Check(copy.VirtualCopyNumber == 1 && copy.IsVirtualCopy, "virtual_copy_number");
            Check(copy.RootFrameId == "frame-1", "virtual_copy_root");
            Check(document.Frames[0].RootFrameId == "frame-1", "virtual_copy_original_is_its_own_root");

            // 이 빌드가 모르는 field 도 넘어가야 합니다.
            Check(
                document.FrameRecord(firstCopy)?["futureFrameValue"]?.GetValue<string>() ==
                    "preserve-me",
                "virtual_copy_keeps_unknown_fields");

            // 사본의 사본도 뿌리는 하나이고 번호는 이어집니다.
            string? secondCopy = document.CreateVirtualCopy(firstCopy);
            Check(secondCopy is not null, "virtual_copy_of_a_copy");
            Check(
                document.Frames[2].VirtualCopyNumber == 2 &&
                    document.Frames[2].RootFrameId == "frame-1",
                "virtual_copy_numbers_continue_within_the_family");
            Check(
                string.Join(',', document.Frames.Select(frame => frame.Id)) ==
                    $"frame-1,{firstCopy},{secondCopy},frame-2",
                "virtual_copy_family_stays_together");

            // 이름은 macOS 와 같은 "사본 N" 모양입니다.
            Check(
                LibraryFrameNaming.DisplayName(document.Frames[1]) == "Frame 1 Copy 1",
                "virtual_copy_display_name");

            Check(document.Save() == CatalogStoreError.None, "virtual_copy_save");
        }

        using LibraryDocument reopened = LibraryDocument.Open(roots).Document!;
        Check(reopened.Frames.Count == 4, "virtual_copy_survives_a_reopen");
        Check(
            reopened.Frames[1].VirtualCopyNumber == 1 &&
                reopened.Frames[1].SourceFrameId == "frame-1",
            "virtual_copy_identity_persisted");
        // 원본을 빼도 사본은 남습니다 — 사본은 카탈로그의 독립된 줄입니다.
        Check(reopened.RemoveFrames(["frame-1"]).Count == 1, "virtual_copy_original_removal");
        Check(reopened.Frames.Count == 3, "virtual_copy_outlives_its_original");
    }

    /// <summary>
    /// 스택은 두 장 미만이 되는 순간 사라져야 합니다. 한 장짜리 스택은 접어도 아무것도 감추지
    /// 않으면서 배지만 남기므로 사용자에게는 고장으로 보입니다.
    /// </summary>
    internal static void VerifyLibraryStacks(string parent)
    {
        StorageRootSet roots = StorageRootResolver.ResolveForTests(
            Path.Combine(parent, "stacks")).Roots!;

        using (CatalogSession seed = CatalogSession.Open(roots).Session!)
        {
            Check(
                seed.Write(new CatalogSnapshot(
                    null,
                    new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
                    {
                        [CatalogEntityTable.Frames] =
                        [
                            new("frame-1", FrameRecord("frame-1", "IMG_0001.tif", 0.0, 1)),
                            new("frame-2", FrameRecord("frame-2", "IMG_0002.tif", 0.0, 2)),
                            new("frame-3", FrameRecord("frame-3", "IMG_0003.tif", 0.0, 3)),
                        ],
                    })).IsSuccess,
                "library_stack_seed");
        }

        string? stackId;
        using (LibraryDocument document = LibraryDocument.Open(roots).Document!)
        {
            Check(document.CreateStack(["frame-1"]) is null, "library_stack_refuses_one_photo");
            Check(
                document.CreateStack(["frame-1", "frame-1"]) is null,
                "library_stack_refuses_a_duplicate");
            stackId = document.CreateStack(["frame-1", "frame-2"])!;
            if (stackId is null)
            {
                Check(false, "library_stack_create");
                return;
            }
            Check(true, "library_stack_create");
            Check(document.Stacks.Count == 1, "library_stack_projected");
            Check(document.Stacks[0].IsCollapsed, "library_stack_starts_collapsed");
            Check(document.StackFor("frame-2")?.Id == stackId, "library_stack_lookup_by_member");
            Check(document.StackFor("frame-3") is null, "library_stack_lookup_misses_outsider");

            // 이미 묶인 사진은 다른 묶음에 들어가지 못합니다.
            Check(
                document.CreateStack(["frame-2", "frame-3"]) is null,
                "library_stack_refuses_an_already_stacked_photo");

            Check(document.ToggleStackCollapsed(stackId), "library_stack_toggle");
            Check(!document.Stacks[0].IsCollapsed, "library_stack_toggle_applied");
            Check(document.ToggleStackCollapsed(stackId), "library_stack_toggle_back");

            // 접힌 묶음은 화면 차례에서 가장 앞선 구성원만 남깁니다.
            LibraryFrameListItem[] items =
            [
                new(document.Frames[0]),
                new(document.Frames[1]),
                new(document.Frames[2]),
            ];
            IReadOnlyList<LibraryFrameListItem> projected =
                LibraryStackProjection.Apply(items, document.Stacks);
            Check(
                projected.Count == 2 && projected[0].Id == "frame-1" &&
                    projected[1].Id == "frame-3",
                "library_stack_collapse_hides_the_rest");

            // 뒤집으면 대표도 뒤집힙니다 — 묶음에 적힌 첫 id 가 아니라 화면 차례입니다.
            LibraryFrameListItem[] reversed = [items[1], items[0], items[2]];
            Check(
                LibraryStackProjection.Apply(reversed, document.Stacks)[0].Id == "frame-2",
                "library_stack_cover_follows_the_sort");

            Check(document.Save() == CatalogStoreError.None, "library_stack_save");
        }

        using (LibraryDocument reopened = LibraryDocument.Open(roots).Document!)
        {
            Check(reopened.Stacks.Count == 1, "library_stack_survives_a_reopen");
            // 두 장짜리에서 한 장을 빼면 묶음이 사라집니다.
            Check(reopened.RemoveFrames(["frame-2"]).Count == 1, "library_stack_removal");
            Check(reopened.Stacks.Count == 0, "library_stack_vanishes_below_two");
            Check(reopened.Save() == CatalogStoreError.None, "library_stack_removal_save");
        }

        using LibraryDocument final = LibraryDocument.Open(roots).Document!;
        Check(final.Stacks.Count == 0, "library_stack_removal_persisted");
    }

    /// <summary>
    /// 사진을 빼면 롤과 묶음의 구성원 목록에서도 빠져야 합니다. frame 행만 지우면 죽은 id 가
    /// 남아, 사용자에게는 "묶음에 두 장인데 한 장만 보인다"로 나타납니다.
    /// </summary>
    internal static void VerifyLibraryFrameRemoval(string parent)
    {
        StorageRootSet roots = StorageRootResolver.ResolveForTests(
            Path.Combine(parent, "frame-removal")).Roots!;

        using (CatalogSession seed = CatalogSession.Open(roots).Session!)
        {
            Check(
                seed.Write(new CatalogSnapshot(
                    null,
                    new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
                    {
                        [CatalogEntityTable.Frames] =
                        [
                            new("frame-1", FrameRecord("frame-1", "IMG_0001.tif", 0.0)),
                            new("frame-2", FrameRecord("frame-2", "IMG_0002.tif", 0.5)),
                        ],
                        [CatalogEntityTable.ManualCollections] =
                        [
                            new("collection-1", new JsonObject
                            {
                                ["id"] = "collection-1",
                                ["name"] = "Keepers",
                                ["frameIDs"] = new JsonArray("frame-1", "frame-2"),
                            }),
                        ],
                    })).IsSuccess,
                "library_removal_seed");
        }

        using (LibraryDocument document = LibraryDocument.Open(roots).Document!)
        {
            Check(
                document.RemoveFrames(["missing-frame"]).Count == 0,
                "library_removal_unknown_id_changes_nothing");
            LibraryFrameRemoval removal = document.RemoveFrames(["frame-1"]);
            Check(removal.Count == 1, "library_removal_reports_one");
            Check(document.Frames.Count == 1, "library_removal_drops_frame");
            Check(document.Frames[0].Id == "frame-2", "library_removal_keeps_the_other");
            Check(
                document.Collections[0].FrameIds.Count == 1 &&
                    document.Collections[0].FrameIds[0] == "frame-2",
                "library_removal_drops_collection_membership");
            Check(document.Save() == CatalogStoreError.None, "library_removal_save");
        }

        using LibraryDocument reopened = LibraryDocument.Open(roots).Document!;
        Check(reopened.RecordCount == 1, "library_removal_persisted");
        Check(
            reopened.Collections.Count == 1 && reopened.Collections[0].FrameIds.Count == 1,
            "library_removal_collection_persisted");
    }

    internal static void VerifyLibraryDocumentDefectProjection(string parent)
    {
        StorageRootSet roots = StorageRootResolver.ResolveForTests(
            Path.Combine(parent, "defect-projection")).Roots!;
        Guid frameId = Guid.Parse("b7c2eea1-50cb-4b71-a97f-0b74df37cdfd");
        byte[] mask = Enumerable.Repeat((byte)255, 16).ToArray();
        DefectEditItem region = new(
            Guid.Parse("a8a0ca90-e261-44fa-bcdf-902c9c6415c2"),
            DefectEditKind.Region,
            Enabled: true,
            Strength: 0.7,
            new DefectEditLabel(DefectEditLabelKind.Guided, 1),
            new DefectEditSummary(
                DefectEditSummaryKind.ClassBreakdown,
                new DefectClassBreakdown(
                    [new DefectClassCount(DefectClassification.Dust, 1)],
                    0.8)),
            new DefectSize(100, 80),
            [])
        {
            RegionMask = new DefectMask(false, mask),
            RegionRoi = new DefectRect(5, 7, 2, 2),
            RegionWidth = 2,
            RegionHeight = 2,
        };
        DefectRecipeSnapshot recipe = DefectRecipeSnapshot.Create(
            frameId,
            recipeRevision: 8,
            new DefectSourceIdentity(456, new string('e', 64)),
            [region]);

        using (CatalogSession session = CatalogSession.Open(roots).Session!)
        {
            Check(session.ReadOrCreate().IsSuccess,
                "library_document_defect_initial_create");
            Check(session.WriteDefectRecipe(recipe).IsSuccess,
                "library_document_defect_sidecar_write");
            JsonObject payload = FrameRecord(
                frameId.ToString("D"),
                "DEFECT_0001.tif",
                0);
            payload["hasDefectEdits"] = true;
            Check(session.Write(new CatalogSnapshot(
                null,
                new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
                {
                    [CatalogEntityTable.Frames] =
                    [new CatalogEntityRow(frameId.ToString("D"), payload)],
                })).IsSuccess,
                "library_document_defect_catalog_write");
        }

        using LibraryDocument document = LibraryDocument.Open(roots).Document!;
        Check(document.Frames.Count == 1 &&
              document.Frames[0] is
                  { DefectRecipe: { RecipeRevision: 8 }, DefectRecipeRevision: 8 } &&
              document.FrameRecord(frameId.ToString("D"))?["hasDefectEdits"]?.GetValue<bool>() == true,
            "library_document_restart_restores_persisted_sidecar");
        DevelopRequestResult request = DevelopRequestFactory.Create(
            document.Frames[0],
            Path.Combine(parent, "defect-output.png"));
        Check(request.IsSuccess &&
              request.Request?.DefectRegions.Count == 1 &&
              request.Request.DefectEditOrder.Count == 1,
            "library_document_restart_reapplies_persisted_recipe");

    }

}
