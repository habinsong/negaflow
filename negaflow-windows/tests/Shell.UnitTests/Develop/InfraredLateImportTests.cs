using Negaflow.Catalog;
using static Negaflow.Shell.UnitTests.DevelopTestResults;
using static Negaflow.Shell.UnitTests.TestAssert;

namespace Negaflow.Shell.UnitTests;

internal static class InfraredLateImportTests
{
    public static void Run()
    {
        string testParent = Path.Combine(AppContext.BaseDirectory, "infrared-late-import-tests");
        string isolatedBase = Path.Combine(testParent, $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        string sourceFolder = Path.Combine(isolatedBase, "source");
        string visibleA = Path.Combine(sourceFolder, "A.tif");
        string infraredA = Path.Combine(sourceFolder, "A_ir.tif");
        string visibleB = Path.Combine(sourceFolder, "B.tif");
        string infraredB = Path.Combine(sourceFolder, "B_ir.tif");
        string visibleC = Path.Combine(sourceFolder, "C.tif");
        string infraredC = Path.Combine(sourceFolder, "C_ir.tif");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;

        try
        {
            Directory.CreateDirectory(sourceFolder);
            File.WriteAllBytes(visibleA, [1]);
            File.WriteAllBytes(visibleB, [2]);

            int scheduledInfraredRuns = 0;
            Task WaitForCancellation(CancellationToken cancellationToken)
            {
                Interlocked.Increment(ref scheduledInfraredRuns);
                return Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
            }

            FakeDispatcher dispatcher = new(accepts: true);
            FakeExporter exporter = new(_ => OkResult());
            using (LibraryHostService host = new(
                dispatcher,
                exporter,
                _ => new LibrarySourceMetadata(1, 64, 48, 3, 16, 1, 1),
                WaitForCancellation))
            {
                Check(host.Open(roots) == LibraryHostState.Open,
                    "late_ir_import_opens_catalog");

                FrameImportPlan importedA = host.Import([visibleA], DevelopmentProcess.C41);
                string frameA = host.Frames.Single().Id;
                Check(importedA.Rows.Count == 1 && host.ActiveFrameId == frameA,
                    "late_ir_import_selects_visible_frame");

                int frameEdited = 0;
                host.FrameEdited += (_, _) => frameEdited++;
                File.WriteAllBytes(infraredA, [3]);
                FrameImportPlan attachedA = host.Import([infraredA], DevelopmentProcess.C41);
                Check(
                    attachedA.Rows.Count == 0 && attachedA.Rejected.Count == 0 &&
                    attachedA.InfraredAttachments.Single().FrameId == frameA &&
                    host.Frames.Single().InfraredPath == infraredA &&
                    host.ActiveFrameId == frameA,
                    "late_ir_file_import_attaches_without_duplicate_frame");
                Check(frameEdited == 1 && scheduledInfraredRuns == 1,
                    "late_ir_file_import_notifies_and_schedules_active_frame");

                FrameImportPlan importedB = host.Import([visibleB], DevelopmentProcess.C41);
                string frameB = importedB.Rows.Single().Id;
                File.WriteAllBytes(infraredB, [4]);
                FolderImportResult attachedB = host.ImportFolders(
                    [sourceFolder],
                    DevelopmentProcess.C41);
                Check(
                    attachedB.IsSuccess && attachedB.AddedFolderCount == 1 &&
                    attachedB.AddedFrameCount == 0 && attachedB.AttachedInfraredCount == 1 &&
                    attachedB.Plan.Frames.InfraredAttachments.Single().FrameId == frameB &&
                    host.Frames.Single(frame => frame.Id == frameB).InfraredPath == infraredB,
                    "late_ir_folder_import_attaches_existing_frame_atomically");
                Check(frameEdited == 2 && scheduledInfraredRuns == 2,
                    "late_ir_folder_import_notifies_and_schedules_active_frame");

                File.WriteAllBytes(infraredC, [5]);
                string strayFrameId = host.Import([infraredC], DevelopmentProcess.C41)
                    .Rows.Single().Id;
                Guid strayFrameGuid = Guid.Parse(strayFrameId);
                DefectEditItem strayEdit = RegionItem();
                Check(host.AppendDefectStroke(
                        strayFrameId,
                        (sourceIdentity, _, nextRevision) => DefectRecipeSnapshot.Create(
                            strayFrameGuid,
                            nextRevision,
                            sourceIdentity,
                            [strayEdit])) == LibraryFrameError.None &&
                      File.Exists(Path.Combine(roots.DefectRecipeRoot, $"{strayFrameId}.json")),
                    "stray_ir_import_repair_seeds_owned_sidecar");
                File.WriteAllBytes(visibleC, [6]);
                string frameC = host.Import([visibleC], DevelopmentProcess.C41)
                    .Rows.Single().Id;
                host.SetSelection([strayFrameId], strayFrameId);
                Check(
                    !host.Import([], DevelopmentProcess.C41).HasAnything &&
                    host.Frames.Any(frame => frame.Id == strayFrameId),
                    "stray_ir_import_repair_does_not_run_for_cancelled_import");
                FolderImportResult repaired = host.ImportFolders(
                    [sourceFolder],
                    DevelopmentProcess.C41);
                Check(
                    repaired.IsSuccess && repaired.AttachedInfraredCount == 1 &&
                    repaired.RemovedStrayInfraredFrameCount == 1 &&
                    repaired.Plan.Frames.RemovedStrayInfraredFrameIds.Single() == strayFrameId &&
                    host.Frames.Count == 3 && host.Frames.All(frame => frame.Id != strayFrameId) &&
                    host.Frames.Single(frame => frame.Id == frameC).InfraredPath == infraredC &&
                    !File.Exists(Path.Combine(roots.DefectRecipeRoot, $"{strayFrameId}.json")),
                    "stray_ir_import_repair_attaches_base_and_removes_legacy_frame");
                Check(host.ActiveFrameId == frameC && scheduledInfraredRuns == 3,
                    "stray_ir_import_repair_moves_selection_to_base_and_schedules_clean");
            }

            using LibraryHostService reopened = new(
                new FakeDispatcher(accepts: true),
                new FakeExporter(_ => OkResult()));
            Check(
                reopened.Open(roots) == LibraryHostState.Open && reopened.Frames.Count == 3 &&
                reopened.Frames.Single(frame => frame.SourcePath == visibleA).InfraredPath == infraredA &&
                reopened.Frames.Single(frame => frame.SourcePath == visibleB).InfraredPath == infraredB &&
                reopened.Frames.Single(frame => frame.SourcePath == visibleC).InfraredPath == infraredC &&
                reopened.Frames.All(frame => frame.SourcePath != infraredC),
                "late_ir_import_persists_attachments_and_stray_repair");
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

    private static DefectEditItem RegionItem()
    {
        byte[] mask = new byte[16];
        mask[5] = GrainMendRegionEdit.DefectMaskWeight;
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
}
