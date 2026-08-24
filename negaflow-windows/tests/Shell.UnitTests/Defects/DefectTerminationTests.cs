using System.Security.Cryptography;
using System.Text.Json.Nodes;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using static Negaflow.Shell.UnitTests.DevelopTestResults;
using static Negaflow.Shell.UnitTests.TestAssert;
using static Negaflow.Shell.UnitTests.TestFrameFactory;

namespace Negaflow.Shell.UnitTests;

internal static class DefectTerminationTests
{
    internal static void Run()
    {
        InfraredOnlyIsDiscarded();
        ScannerAutoBakesInPlaceAndExcludesInfrared();
        SharedScannerBakesToOwnedScan();
        ImportedGuidedBakesToOwnedScan();
        CatalogFailureRestoresScannerSource();
    }

    private static void SharedScannerBakesToOwnedScan()
    {
        RunIsolated("shared-scanner", (isolatedBase, roots) =>
        {
            Guid editedId = Guid.Parse("b1b2c3d4-06dd-4196-a48e-483276dff37f");
            Guid sharedId = Guid.Parse("c1c2d3e4-0ef4-4ac3-a342-a3340cb0161d");
            byte[] original = [5, 10, 15, 20];
            byte[] baked = [6, 12, 18, 24, 30];
            string sourcePath = Source(isolatedBase, "SHARED.tiff", original);
            DefectRecipeSnapshot recipe = Recipe(
                editedId, sourcePath, [RegionItem(automatic: true)]);
            JsonObject edited = Record(editedId, sourcePath, FrameSourceKind.ScannerTiff);
            JsonObject shared = Record(sharedId, sourcePath, FrameSourceKind.ScannerTiff);
            using (CatalogSession session = CatalogSession.Open(roots).Session!)
            {
                Check(session.Write(Catalog(edited, shared)).IsSuccess,
                    "defect_termination_shared_seed_catalog");
            }
            string expected = Path.Combine(
                Scans(isolatedBase),
                "SHARED-cleaned-B1B2C3D4.tiff");
            FakeExporter exporter = BakeExporter(baked);

            using LibraryHostService host = Host(exporter);
            Check(host.Open(roots) == LibraryHostState.Open,
                "defect_termination_shared_open");
            _ = InstallRecipe(host, editedId, recipe.Items);
            LibraryDefectTerminationResult result = host
                .PrepareForTerminationAsync(Scans(isolatedBase))
                .GetAwaiter()
                .GetResult();
            LibraryFrameSnapshot editedFrame = host.Frames.Single(frame =>
                frame.Id == editedId.ToString("D"));
            LibraryFrameSnapshot sharedFrame = host.Frames.Single(frame =>
                frame.Id == sharedId.ToString("D"));
            Check(result.IsSuccess &&
                  File.ReadAllBytes(sourcePath).SequenceEqual(original) &&
                  File.ReadAllBytes(expected).SequenceEqual(baked) &&
                  editedFrame.SourcePath == expected &&
                  editedFrame.DefectRecipe is null &&
                  sharedFrame.SourcePath == sourcePath &&
                  !SidecarExists(roots, editedId),
                "defect_termination_shared_scanner_preserves_other_frame_source");
        });
    }

    private static void InfraredOnlyIsDiscarded()
    {
        RunIsolated("ir-only", (isolatedBase, roots) =>
        {
            Guid frameId = Guid.Parse("02fe2759-bc26-4e2d-8b4d-cdca8cb7e760");
            string sourcePath = Source(isolatedBase, "IR_ONLY.tiff", [1, 3, 5, 7]);
            DefectRecipeSnapshot recipe = Recipe(frameId, sourcePath, [InfraredItem()]);
            Seed(roots, frameId, sourcePath, FrameSourceKind.ScannerTiff);
            FakeExporter exporter = BakeExporter([9, 9, 9, 9]);

            using (LibraryHostService host = Host(exporter))
            {
                Check(host.Open(roots) == LibraryHostState.Open,
                    "defect_termination_ir_open");
                _ = InstallRecipe(host, frameId, recipe.Items);
                LibraryDefectTerminationResult result = host
                    .PrepareForTerminationAsync(Scans(isolatedBase))
                    .GetAwaiter()
                    .GetResult();
                Check(result.IsSuccess &&
                      exporter.BakeCallCount == 0 &&
                      host.Frames.Single().DefectRecipe is null &&
                      File.ReadAllBytes(sourcePath).SequenceEqual(
                          new byte[] { 1, 3, 5, 7 }) &&
                      !SidecarExists(roots, frameId),
                    "defect_termination_ir_discards_recipe_without_bake");
            }

            using LibraryHostService reopened = Host(BakeExporter([8]));
            Check(reopened.Open(roots) == LibraryHostState.Open &&
                  reopened.Frames.Single().DefectRecipe is null,
                "defect_termination_ir_reopen_has_no_persisted_layer");
        });
    }

    private static void ScannerAutoBakesInPlaceAndExcludesInfrared()
    {
        RunIsolated("scanner-auto", (isolatedBase, roots) =>
        {
            Guid frameId = Guid.Parse("9b108d19-0487-442d-bd30-808b2e3dd230");
            byte[] original = [2, 4, 6, 8];
            byte[] baked = [10, 20, 30, 40, 50];
            string sourcePath = Source(isolatedBase, "AUTO.tiff", original);
            DefectEditItem automatic = RegionItem(automatic: true);
            DefectRecipeSnapshot recipe = Recipe(
                frameId, sourcePath, [automatic, InfraredItem()]);
            Seed(roots, frameId, sourcePath, FrameSourceKind.ScannerTiff);
            FakeExporter exporter = BakeExporter(baked);

            using (LibraryHostService host = Host(exporter))
            {
                Check(host.Open(roots) == LibraryHostState.Open,
                    "defect_termination_scanner_open");
                _ = InstallRecipe(host, frameId, recipe.Items);
                host.DefectLiveStrengths.Set(frameId.ToString("D"), automatic.Id, 0.4);
                int callerThread = Environment.CurrentManagedThreadId;
                LibraryDefectTerminationResult result = host
                    .PrepareForTerminationAsync(Scans(isolatedBase))
                    .GetAwaiter()
                    .GetResult();
                Check(result.IsSuccess &&
                      exporter.BakeCallCount == 1 &&
                      exporter.BakeThreadId != callerThread &&
                      exporter.LastBakeRequest is
                      {
                          DefectRegions.Count: 1,
                          DefectInfrared.Count: 0,
                          DefectEditOrder.Count: 1,
                      } request &&
                      request.DefectEditOrder[0].Kind == DevelopDefectEditKind.Region &&
                      request.SourcePath == sourcePath &&
                      File.ReadAllBytes(sourcePath).SequenceEqual(baked) &&
                      host.Frames.Single() is
                      {
                          SourcePath: var currentPath,
                          DefectRecipe: null,
                      } &&
                      currentPath == sourcePath &&
                      host.DefectLiveStrengths.Get(frameId.ToString("D")) is null &&
                      !SidecarExists(roots, frameId),
                    "defect_termination_scanner_bakes_auto_in_place_without_ir");
            }

            using LibraryHostService reopened = Host(BakeExporter([8]));
            Check(reopened.Open(roots) == LibraryHostState.Open &&
                  reopened.Frames.Single() is
                  {
                      SourcePath: var reopenedPath,
                      DefectRecipe: null,
                  } &&
                  reopenedPath == sourcePath,
                "defect_termination_scanner_reopen_keeps_baked_source_only");
        });
    }

    private static void ImportedGuidedBakesToOwnedScan()
    {
        RunIsolated("imported-guided", (isolatedBase, roots) =>
        {
            Guid frameId = Guid.Parse("a1b2c3d4-1f55-4ec0-9209-44903ea71773");
            byte[] original = [11, 22, 33, 44];
            byte[] baked = [7, 14, 21, 28, 35];
            string sourcePath = Source(isolatedBase, "GUIDED.dng", original);
            DefectRecipeSnapshot recipe = Recipe(
                frameId, sourcePath, [RegionItem(automatic: false)]);
            Seed(roots, frameId, sourcePath, FrameSourceKind.ImportedFile);
            FakeExporter exporter = BakeExporter(baked);
            string expected = Path.Combine(
                Scans(isolatedBase),
                "GUIDED-cleaned-A1B2C3D4.tiff");

            using (LibraryHostService host = Host(exporter))
            {
                Check(host.Open(roots) == LibraryHostState.Open,
                    "defect_termination_imported_open");
                _ = InstallRecipe(host, frameId, recipe.Items);
                LibraryDefectTerminationResult result = host
                    .PrepareForTerminationAsync(Scans(isolatedBase))
                    .GetAwaiter()
                    .GetResult();
                Check(result.IsSuccess &&
                      exporter.BakeCallCount == 1 &&
                      File.ReadAllBytes(sourcePath).SequenceEqual(original) &&
                      File.Exists(expected) &&
                      File.ReadAllBytes(expected).SequenceEqual(baked) &&
                      host.Frames.Single() is
                      {
                          SourcePath: var currentPath,
                          DefectRecipe: null,
                      } &&
                      currentPath == expected &&
                      !SidecarExists(roots, frameId),
                    "defect_termination_imported_repoints_guided_to_owned_scan");
            }

            using LibraryHostService reopened = Host(BakeExporter([8]));
            Check(reopened.Open(roots) == LibraryHostState.Open &&
                  reopened.Frames.Single() is
                  {
                      SourcePath: var reopenedPath,
                      DefectRecipe: null,
                  } &&
                  reopenedPath == expected,
                "defect_termination_imported_reopen_uses_owned_scan_only");
        });
    }

    private static void CatalogFailureRestoresScannerSource()
    {
        RunIsolated("rollback", (isolatedBase, roots) =>
        {
            Guid frameId = Guid.Parse("7dbfe330-29b4-45ad-9e9a-5993ae9c0ead");
            byte[] original = [13, 17, 19, 23];
            string sourcePath = Source(isolatedBase, "ROLLBACK.tiff", original);
            DefectRecipeSnapshot recipe = Recipe(
                frameId, sourcePath, [RegionItem(automatic: true)]);
            Seed(roots, frameId, sourcePath, FrameSourceKind.ScannerTiff);
            FakeExporter exporter = BakeExporter([29, 31, 37, 41, 43]);

            using LibraryHostService host = Host(exporter);
            Check(host.Open(roots) == LibraryHostState.Open,
                "defect_termination_rollback_open");
            DefectRecipeSnapshot installed = InstallRecipe(host, frameId, recipe.Items);
            using FileStream sidecarLock = new(
                Path.Combine(roots.DefectRecipeRoot, $"{frameId:D}.json"),
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read);
            LibraryDefectTerminationResult result = host
                .PrepareForTerminationAsync(Scans(isolatedBase))
                .GetAwaiter()
                .GetResult();
            Check(result.Error == LibraryDefectTerminationError.CatalogCommitFailed &&
                  exporter.BakeCallCount == 1 &&
                  File.ReadAllBytes(sourcePath).SequenceEqual(original) &&
                  host.Frames.Single().DefectRecipe?.RecipeSha256 == installed.RecipeSha256 &&
                  SidecarExists(roots, frameId),
                "defect_termination_catalog_failure_rolls_back_source_and_recipe");
        });
    }

    private static LibraryHostService Host(FakeExporter exporter) => new(
        new FakeDispatcher(accepts: true),
        exporter,
        ReadMetadata);

    private static FakeExporter BakeExporter(byte[] baked) => new(
        _ => OkResult(),
        bakeBehaviour: request =>
        {
            File.WriteAllBytes(request.DestinationPath, baked);
            return OkResult();
        });

    private static LibrarySourceMetadata? ReadMetadata(string path) =>
        File.Exists(path)
            ? new LibrarySourceMetadata(
                (ulong)new FileInfo(path).Length,
                4,
                2,
                3,
                16,
                1,
                1)
            : null;

    private static string Source(string isolatedBase, string name, byte[] bytes)
    {
        string path = Path.Combine(isolatedBase, "sources", name);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllBytes(path, bytes);
        return path;
    }

    private static string Scans(string isolatedBase) =>
        Path.Combine(isolatedBase, "scans");

    private static DefectRecipeSnapshot Recipe(
        Guid frameId,
        string sourcePath,
        IReadOnlyList<DefectEditItem> items)
    {
        byte[] source = File.ReadAllBytes(sourcePath);
        return DefectRecipeSnapshot.Create(
            frameId,
            4,
            new DefectSourceIdentity(
                (ulong)source.Length,
                Convert.ToHexString(SHA256.HashData(source)).ToLowerInvariant()),
            items);
    }

    private static void Seed(
        StorageRootSet roots,
        Guid frameId,
        string sourcePath,
        FrameSourceKind sourceKind)
    {
        JsonObject plain = Record(frameId, sourcePath, sourceKind);
        using CatalogSession session = CatalogSession.Open(roots).Session!;
        Check(session.Write(Catalog(plain)).IsSuccess,
            $"defect_termination_seed_catalog_{frameId:D}");
    }

    private static DefectRecipeSnapshot InstallRecipe(
        LibraryHostService host,
        Guid frameId,
        IReadOnlyList<DefectEditItem> items)
    {
        DevelopPanelState panel = new(
            host,
            new ToneLimits(5.0f, 1.0f, 2.0f, 0.0, 1.0),
            new NegativeLimits(0.001f, 1.0f));
        Check(panel.Select(frameId.ToString("D")),
            $"defect_termination_select_{frameId:D}");
        foreach (DefectEditItem item in items)
        {
            Check(panel.AcceptDefectRegion(item) == LibraryFrameError.None,
                $"defect_termination_append_{frameId:D}_{item.Id:D}");
        }
        return panel.SelectedFrame!.DefectRecipe!;
    }

    private static JsonObject Record(
        Guid frameId,
        string sourcePath,
        FrameSourceKind sourceKind)
    {
        JsonObject record = FrameRecord(
            frameId.ToString("D"),
            Path.GetFileName(sourcePath),
            exposure: 0.0);
        record["rawScanPath"] = sourcePath;
        record["sourceKind"] = sourceKind == FrameSourceKind.ScannerTiff
            ? "scanner"
            : "imported";
        record[LibraryFrameReader.SourceMetadataName] =
            LibrarySourceMetadataJson.Write(ReadMetadata(sourcePath)!.Value);
        return record;
    }

    private static CatalogSnapshot Catalog(params JsonObject[] records) => new(
        null,
        new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
        {
            [CatalogEntityTable.Frames] =
                records.Select(record => new CatalogEntityRow(
                    record["id"]!.GetValue<string>(), record)).ToArray(),
        });

    private static DefectEditItem RegionItem(bool automatic)
    {
        byte[] mask = new byte[4 * 4 * 4];
        mask[20] = mask[21] = mask[22] = mask[23] = 255;
        return GrainMendRegionEdit.From(
            mask.Where((_, index) => index % 4 == 0).ToArray(),
            4,
            4,
            20,
            10,
            0,
            0,
            20,
            10,
            1,
            automatic)!;
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

    private static bool SidecarExists(StorageRootSet roots, Guid frameId) =>
        File.Exists(Path.Combine(roots.DefectRecipeRoot, $"{frameId:D}.json"));

    private static void RunIsolated(
        string name,
        Action<string, StorageRootSet> test)
    {
        string testParent = Path.Combine(Path.GetTempPath(), "negaflow-gm-termination-tests");
        string isolatedBase = Path.Combine(testParent, $"{name}-{Guid.NewGuid():N}");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;
        try
        {
            test(isolatedBase, roots);
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
}
