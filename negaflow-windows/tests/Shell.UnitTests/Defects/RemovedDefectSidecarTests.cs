using System.Text.Json.Nodes;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using static Negaflow.Shell.UnitTests.DevelopTestResults;
using static Negaflow.Shell.UnitTests.TestAssert;
using static Negaflow.Shell.UnitTests.TestFrameFactory;

namespace Negaflow.Shell.UnitTests;

internal static class RemovedDefectSidecarTests
{
    internal static void Run()
    {
        UndoOwnsSidecarUntilDepthEviction();
        TerminationPurgesRemovedSidecar();
        TerminationPurgeFailurePreservesUndo();
    }

    private static void UndoOwnsSidecarUntilDepthEviction()
    {
        RunIsolated("depth", (isolatedBase, roots, removedId, survivorId) =>
        {
            Seed(roots, isolatedBase, removedId, survivorId);
            using LibraryHostService host = Host();
            Check(host.Open(roots) == LibraryHostState.Open,
                "removed_defect_sidecar_depth_open");
            InstallRecipe(host, removedId);
            Check(host.RemoveFrames([removedId.ToString("D")]) == 1 &&
                  SidecarExists(roots, removedId),
                "removed_defect_sidecar_retained_for_undo");
            Check(host.Undo() == LibraryHostService.UndoActions.RemoveFrames &&
                  host.Frames.Single(frame => frame.Id == removedId.ToString("D"))
                      .DefectRecipe?.Items.Count == 3 &&
                  SidecarExists(roots, removedId),
                "removed_defect_sidecar_undo_restores_session_recipe");
            Check(host.Redo() == LibraryHostService.UndoActions.RemoveFrames &&
                  host.Frames.All(frame => frame.Id != removedId.ToString("D")) &&
                  SidecarExists(roots, removedId),
                "removed_defect_sidecar_redo_keeps_undo_owner");

            for (int index = 0; index < LibraryUndoStack.MaximumDepth - 1; ++index)
            {
                Check(EditSurvivor(host, survivorId, index),
                    $"removed_defect_sidecar_depth_edit_{index}");
            }
            Check(SidecarExists(roots, removedId),
                "removed_defect_sidecar_kept_at_depth_boundary");
            Check(EditSurvivor(host, survivorId, LibraryUndoStack.MaximumDepth),
                "removed_defect_sidecar_depth_eviction_edit");
            Check(!SidecarExists(roots, removedId),
                "removed_defect_sidecar_purged_after_last_undo_owner_evicted");
        });
    }

    private static void TerminationPurgesRemovedSidecar()
    {
        RunIsolated("termination", (isolatedBase, roots, removedId, survivorId) =>
        {
            Seed(roots, isolatedBase, removedId, survivorId);
            using LibraryHostService host = Host();
            Check(host.Open(roots) == LibraryHostState.Open,
                "removed_defect_sidecar_termination_open");
            InstallRecipe(host, removedId);
            Check(host.RemoveFrames([removedId.ToString("D")]) == 1 &&
                  SidecarExists(roots, removedId),
                "removed_defect_sidecar_termination_seed_removal");
            LibraryDefectTerminationResult result = host
                .PrepareForTerminationAsync(Path.Combine(isolatedBase, "scans"))
                .GetAwaiter()
                .GetResult();
            Check(result.IsSuccess &&
                  !SidecarExists(roots, removedId) &&
                  !host.CanUndo,
                "removed_defect_sidecar_termination_purges_and_releases_history");
        });
    }

    private static void TerminationPurgeFailurePreservesUndo()
    {
        RunIsolated("locked", (isolatedBase, roots, removedId, survivorId) =>
        {
            Seed(roots, isolatedBase, removedId, survivorId);
            using LibraryHostService host = Host();
            Check(host.Open(roots) == LibraryHostState.Open,
                "removed_defect_sidecar_locked_open");
            InstallRecipe(host, removedId);
            Check(host.RemoveFrames([removedId.ToString("D")]) == 1,
                "removed_defect_sidecar_locked_seed_removal");
            string sidecarPath = Path.Combine(
                roots.DefectRecipeRoot,
                $"{removedId:D}.json");
            LibraryDefectTerminationResult result;
            using (FileStream sidecarLock = new(
                       sidecarPath,
                       FileMode.Open,
                       FileAccess.Read,
                       FileShare.Read))
            {
                result = host
                    .PrepareForTerminationAsync(Path.Combine(isolatedBase, "scans"))
                    .GetAwaiter()
                    .GetResult();
            }
            Check(result.Error == LibraryDefectTerminationError.OrphanPurgeFailed &&
                  result.SidecarError != DefectSidecarError.None &&
                  SidecarExists(roots, removedId) &&
                  host.CanUndo,
                "removed_defect_sidecar_locked_blocks_termination_without_dropping_history");
            Check(host.Undo() == LibraryHostService.UndoActions.RemoveFrames &&
                  host.Frames.Single(frame => frame.Id == removedId.ToString("D"))
                      .DefectRecipe?.Items.Count == 3,
                "removed_defect_sidecar_locked_failure_remains_undoable");
        });
    }

    private static bool EditSurvivor(
        LibraryHostService host,
        Guid survivorId,
        int index) => host.EditUndoable(
            survivorId.ToString("D"),
            LibraryHostService.UndoActions.DevelopAdjustment,
            new LibraryFrameEdit(
                new ToneAdjustment(index * 0.01, 0, 0, 0, 0, 0),
                null)) == LibraryFrameError.None;

    private static LibraryHostService Host() => new(
        new FakeDispatcher(accepts: true),
        new FakeExporter(_ => OkResult()),
        TestSourceMetadata);

    private static void Seed(
        StorageRootSet roots,
        string isolatedBase,
        Guid removedId,
        Guid survivorId)
    {
        string removedPath = Source(isolatedBase, "REMOVED.tiff", [1, 4, 9, 16]);
        string survivorPath = Source(isolatedBase, "SURVIVOR.tiff", [2, 3, 5, 7]);
        JsonObject removed = Record(removedId, removedPath);
        JsonObject survivor = Record(survivorId, survivorPath);
        using CatalogSession session = CatalogSession.Open(roots).Session!;
        Check(session.Write(Catalog(removed, survivor)).IsSuccess,
            "removed_defect_sidecar_seed_catalog");
    }

    private static void InstallRecipe(LibraryHostService host, Guid frameId)
    {
        DevelopPanelState panel = new(
            host,
            new ToneLimits(5.0f, 1.0f, 2.0f, 0.0, 1.0),
            new NegativeLimits(0.001f, 1.0f));
        Check(panel.Select(frameId.ToString("D")),
            $"removed_defect_sidecar_select_{frameId:D}");
        foreach (DefectEditItem item in new[]
                 {
                     Region(automatic: true),
                     Region(automatic: false),
                     Infrared(),
                 })
        {
            Check(panel.AcceptDefectRegion(item) == LibraryFrameError.None,
                $"removed_defect_sidecar_append_{frameId:D}_{item.Id:D}");
        }
    }

    private static DefectEditItem Region(bool automatic) =>
        GrainMendRegionEdit.From(
            [0, 0, 0, 0, 0, 255, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
            4, 4, 20, 10, 0, 0, 20, 10, 1, automatic)!;

    private static DefectEditItem Infrared()
    {
        byte[] mask = new byte[4 * 4 * 4];
        mask[0] = mask[1] = mask[2] = mask[3] = 255;
        return new DefectEditItem(
            Guid.NewGuid(),
            DefectEditKind.Infrared,
            true,
            1.0,
            new DefectEditLabel(DefectEditLabelKind.Infrared, 1),
            new DefectEditSummary(
                DefectEditSummaryKind.ClassBreakdown,
                new DefectClassBreakdown(
                    [new DefectClassCount(DefectClassification.Dust, 1)],
                    1.0)),
            new DefectSize(4, 4),
            [])
        {
            Clusters =
            [new DefectCluster(new DefectRect(0, 0, 4, 4), new DefectMask(false, mask), 4, 4)],
        };
    }

    private static JsonObject Record(Guid frameId, string sourcePath)
    {
        JsonObject record = FrameRecord(
            frameId.ToString("D"), Path.GetFileName(sourcePath), 0.0);
        record["rawScanPath"] = sourcePath;
        return record;
    }

    private static CatalogSnapshot Catalog(params JsonObject[] records) => new(
        null,
        new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
        {
            [CatalogEntityTable.Frames] = records.Select(record =>
                new CatalogEntityRow(record["id"]!.GetValue<string>(), record)).ToArray(),
        });

    private static string Source(string isolatedBase, string name, byte[] bytes)
    {
        string path = Path.Combine(isolatedBase, "sources", name);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllBytes(path, bytes);
        return path;
    }

    private static bool SidecarExists(StorageRootSet roots, Guid frameId) =>
        File.Exists(Path.Combine(roots.DefectRecipeRoot, $"{frameId:D}.json"));

    private static void RunIsolated(
        string name,
        Action<string, StorageRootSet, Guid, Guid> test)
    {
        string parent = Path.Combine(Path.GetTempPath(), "negaflow-gm-removed-sidecar-tests");
        string isolatedBase = Path.Combine(parent, $"{name}-{Guid.NewGuid():N}");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;
        Guid removedId = Guid.NewGuid();
        Guid survivorId = Guid.NewGuid();
        try
        {
            test(isolatedBase, roots, removedId, survivorId);
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
}
