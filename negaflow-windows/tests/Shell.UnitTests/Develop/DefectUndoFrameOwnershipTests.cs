using System.Text.Json.Nodes;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using static Negaflow.Shell.UnitTests.DevelopTestResults;
using static Negaflow.Shell.UnitTests.TestAssert;
using static Negaflow.Shell.UnitTests.TestFrameFactory;

namespace Negaflow.Shell.UnitTests;

internal static class DefectUndoFrameOwnershipTests
{
    internal static void Run()
    {
        string testParent = Path.Combine(Path.GetTempPath(), "negaflow-gm-undo-frame-tests");
        string isolatedBase = Path.Combine(testParent, Guid.NewGuid().ToString("N"));
        StorageRootSet roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;
        Guid firstId = Guid.Parse("035e0331-1555-4a79-a0dc-e96f6c032078");
        Guid secondId = Guid.Parse("d791ed81-b418-44f7-adcd-525998192ad5");
        try
        {
            string firstPath = WriteSource(isolatedBase, "FRAME_A.tif", [1, 3, 5, 7]);
            string secondPath = WriteSource(isolatedBase, "FRAME_B.tif", [2, 4, 6, 8]);
            using (CatalogSession seed = CatalogSession.Open(roots).Session!)
            {
                Check(seed.Write(new CatalogSnapshot(
                    null,
                    new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
                    {
                        [CatalogEntityTable.Frames] =
                        [
                            new(firstId.ToString("D"), Record(firstId, firstPath, 1)),
                            new(secondId.ToString("D"), Record(secondId, secondPath, 2)),
                        ],
                    })).IsSuccess, "defect_undo_frame_seed_catalog");
            }

            using LibraryHostService host = new(
                new FakeDispatcher(accepts: true),
                new FakeExporter(_ => OkResult()),
                TestSourceMetadata);
            Check(host.Open(roots) == LibraryHostState.Open,
                "defect_undo_frame_open");
            DevelopPanelState panel = new(
                host,
                new ToneLimits(5.0f, 1.0f, 2.0f, 0.0, 1.0),
                new NegativeLimits(0.001f, 1.0f));
            Check(panel.Select(firstId.ToString("D")),
                "defect_undo_frame_select_a");
            Check(panel.AcceptDefectRegion(AutomaticItem()) == LibraryFrameError.None &&
                  panel.CanUndoDefectEdit,
                "defect_undo_frame_a_edit_enables_a");

            Check(panel.Select(secondId.ToString("D")) && !panel.CanUndoDefectEdit,
                "defect_undo_frame_a_history_does_not_enable_b");
            Check(!panel.UndoDefectEdit() &&
                  host.Frames.Single(frame => frame.Id == firstId.ToString("D"))
                      .DefectRecipe?.Items.Count == 1 &&
                  host.Frames.Single(frame => frame.Id == secondId.ToString("D"))
                      .DefectRecipe is null,
                "defect_undo_frame_b_cannot_undo_a");

            Check(panel.Select(firstId.ToString("D")) &&
                  panel.CanUndoDefectEdit &&
                  panel.UndoDefectEdit(),
                "defect_undo_frame_a_can_undo_own_history");
            Check(host.Frames.Single(frame => frame.Id == firstId.ToString("D")) is
                      { DefectRecipe: null, DefectRecipeRevision: 2 } &&
                  host.Frames.Single(frame => frame.Id == secondId.ToString("D"))
                      .DefectRecipe is null,
                "defect_undo_frame_a_undo_preserves_b");
        }
        finally
        {
            if (Directory.Exists(isolatedBase) &&
                StoragePathPolicy.IsLexicallyContained(testParent, isolatedBase))
            {
                Directory.Delete(isolatedBase, recursive: true);
            }
        }
    }

    private static string WriteSource(string isolatedBase, string name, byte[] bytes)
    {
        string path = Path.Combine(isolatedBase, "scans", name);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllBytes(path, bytes);
        return path;
    }

    private static JsonObject Record(Guid frameId, string sourcePath, int scanIndex)
    {
        JsonObject record = FrameRecord(
            frameId.ToString("D"),
            Path.GetFileName(sourcePath),
            exposure: 0.0,
            scanIndex);
        record["rawScanPath"] = sourcePath;
        return record;
    }

    private static DefectEditItem AutomaticItem() =>
        GrainMendRegionEdit.From(
            [0, 0, 0, 0, 0, 255, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
            4,
            4,
            20,
            10,
            0,
            0,
            20,
            10,
            1,
            automatic: true)!;
}
