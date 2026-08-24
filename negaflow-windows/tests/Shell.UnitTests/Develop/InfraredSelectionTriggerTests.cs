using System.Text.Json.Nodes;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using static Negaflow.Shell.UnitTests.DevelopTestResults;
using static Negaflow.Shell.UnitTests.TestAssert;
using static Negaflow.Shell.UnitTests.TestFrameFactory;

namespace Negaflow.Shell.UnitTests;

internal static class InfraredSelectionTriggerTests
{
    public static void Run()
    {
        string parent = Path.Combine(AppContext.BaseDirectory, "infrared-selection-trigger-tests");
        string isolatedBase = Path.Combine(parent, $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;
        Guid frameId = Guid.Parse("74a46a94-641f-4145-8f4c-bfb908f5737a");
        string frameIdText = frameId.ToString("D");
        string sourcePath = Path.Combine(isolatedBase, "visible.tif");
        string infraredPath = Path.Combine(isolatedBase, "infrared.tif");
        try
        {
            Directory.CreateDirectory(isolatedBase);
            File.WriteAllBytes(sourcePath, [1, 3, 5, 7]);
            File.WriteAllBytes(infraredPath, [2, 4, 6, 8]);
            JsonObject record = FrameRecord(frameIdText, "visible.tif", 0.0);
            record[LibraryFrameReader.SourcePathName] = sourcePath;
            record[LibraryFrameReader.InfraredPathName] = infraredPath;
            record["filmType"] = "bwNegative";
            record["params"]!.AsObject()["filmType"] = "bwNegative";
            using (CatalogSession seed = CatalogSession.Open(roots).Session!)
            {
                Check(seed.Write(new CatalogSnapshot(
                    null,
                    new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
                    {
                        [CatalogEntityTable.Frames] = [new(frameIdText, record)],
                    })).IsSuccess, "infrared_process_trigger_seed");
            }

            int selectionDelayCount = 0;
            using LibraryHostService host = new(
                new FakeDispatcher(accepts: true),
                new FakeExporter(_ => OkResult()),
                TestSourceMetadata,
                token =>
                {
                    Interlocked.Increment(ref selectionDelayCount);
                    return Task.Delay(Timeout.Infinite, token);
                });
            host.Open(roots);
            host.SetSelection([frameIdText], frameIdText);
            Check(selectionDelayCount == 0,
                "infrared_process_trigger_bw_selection_stays_ineligible");

            DevelopPanelState panel = new(
                host,
                new ToneLimits(5.0F, 1.0F, 2.0F, 0.0, 1.0),
                new NegativeLimits(0.001F, 1.0F));
            Check(panel.Select(frameIdText), "infrared_process_trigger_panel_select");
            Check(
                panel.SetDevelopmentProcess(DevelopmentProcess.C41) == LibraryFrameError.None &&
                panel.DevelopmentProcess == DevelopmentProcess.C41 &&
                panel.LastInfraredClean.Message == InfraredCleanMessage.None &&
                selectionDelayCount == 0,
                "infrared_process_edit_does_not_reenter_selection_clean");

            Check(host.AppendDefectStroke(
                    frameIdText,
                    (identity, _, revision) => DefectRecipeSnapshot.Create(
                        frameId, revision, identity, [InfraredItem()]),
                    LibraryDefectHistoryMode.Exact) == LibraryFrameError.None &&
                  panel.Select(frameIdText) &&
                  panel.HasDefectEdits(DefectEditKind.Infrared),
                "infrared_explicit_delete_seed_current_session_item");
            Check(
                panel.RemoveDefectEdits(DefectEditKind.Infrared) == LibraryFrameError.None &&
                panel.SelectedFrame?.DefectRecipe?.Items.Any(
                    item => item.Kind == DefectEditKind.Infrared) != true &&
                selectionDelayCount == 0,
                "infrared_explicit_delete_does_not_reenter_selection_clean");

            Check(host.AppendDefectStroke(
                    frameIdText,
                    (identity, _, revision) => DefectRecipeSnapshot.Create(
                        frameId, revision, identity, [InfraredItem()]),
                    LibraryDefectHistoryMode.Exact) == LibraryFrameError.None &&
                  panel.Select(frameIdText) &&
                  panel.CreateVirtualCopy(),
                "infrared_virtual_copy_create_with_item");
            LibraryFrameSnapshot? copy = panel.SelectedFrame;
            Check(copy is not null &&
                  copy.Id != frameIdText &&
                  copy.InfraredPath == infraredPath &&
                  copy.DefectRecipe?.Items.Any(
                      item => item.Kind == DefectEditKind.Infrared) == true &&
                  selectionDelayCount == 0,
                "infrared_virtual_copy_keeps_companion_and_item_without_detection");
            Check(
                panel.RemoveDefectEdits(DefectEditKind.Infrared) == LibraryFrameError.None &&
                panel.SelectedFrame?.Id == copy?.Id &&
                panel.SelectedFrame?.DefectRecipe?.Items.Any(
                    item => item.Kind == DefectEditKind.Infrared) != true &&
                selectionDelayCount == 0,
                "infrared_virtual_copy_delete_does_not_reenter_selection_clean");
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
}
