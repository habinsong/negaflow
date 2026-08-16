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

internal static class FrameImportTests
{
    public static void Run()
    {
        VerifyFrameImport();
        VerifyFolderImport();
    }

    private static void VerifyFrameImport()
    {
        int counter = 0;
        string NextId() => $"import-{++counter}";
        bool Exists(string path) => !path.Contains("missing", StringComparison.Ordinal);

        FrameImportPlan plan = FrameImport.Plan(
            [@"C:\scans\a.tif", @"C:\scans\b.tif"],
            [],
            DevelopmentProcess.C41,
            Exists,
            NextId);

        Check(plan.Rows.Count == 2, "import_plans_both_files");
        Check(plan.Rejected.Count == 0, "import_rejects_nothing");
        Check(plan.Rows[0].Id == "import-1", "import_assigns_id");
        Check(
            plan.Rows[0].Payload["rawScanPath"]!.GetValue<string>() == @"C:\scans\a.tif",
            "import_records_source_path");
        Check(
            plan.Rows[0].Payload["sourceKind"]!.GetValue<string>() == "imported",
            "import_records_transport");
        Check(
            plan.Rows[0].Payload["customDisplayName"]!.GetValue<string>() == "a.tif",
            "import_records_display_name");
        Check(plan.Rows[0].Payload["scanIndex"]!.GetValue<int>() == 0, "import_first_scan_index");
        Check(plan.Rows[1].Payload["scanIndex"]!.GetValue<int>() == 1, "import_second_scan_index");
        // route 는 DevelopRouteWriter 가 씁니다. 여기서 직접 쓰면 legacy marker 규칙이 갈라집니다.
        Check(
            plan.Rows[0].Payload["filmType"]!.GetValue<string>() == "colorNegative",
            "import_route_film_type");
        Check(
            plan.Rows[0].Payload["sourceSignalKind"]!.GetValue<string>() == "filmNegativeScan",
            "import_route_signal");

        // 가져온 frame 은 Auto recipe로 읽히며 resolver가 실제 입력에서 base를 결정합니다.
        LibraryFrameReadResult read = ReadImported(plan.Rows[0].Payload);
        Check(read.IsSuccess, "import_record_is_readable");
        Check(read.Frame?.CanDevelop == true, "import_record_uses_auto_base");

        FrameImportPlan metadataPlan = FrameImport.Plan(
            [@"C:\scans\metadata.tif"],
            [],
            DevelopmentProcess.C41,
            Exists,
            NextId,
            _ => new LibrarySourceMetadata(4096, 64, 32, 3, 16, 1, 1));
        Check(
            ReadImported(metadataPlan.Rows[0].Payload).Frame?.SourceMetadata ==
                new LibrarySourceMetadata(4096, 64, 32, 3, 16, 1, 1),
            "import_persists_native_source_metadata");
        Check(
            FrameImport.Plan(
                [@"C:\scans\unsupported.tif"],
                [],
                DevelopmentProcess.C41,
                Exists,
                NextId,
                _ => null).Rejected.Single().Refusal == FrameImportRefusal.UnsupportedImage,
            "import_rejects_unprobed_source");

        LibraryFrameSnapshot existing = read.Frame!;
        FrameImportPlan again = FrameImport.Plan(
            [@"C:\scans\a.tif", @"C:\scans\c.tif"],
            [existing],
            DevelopmentProcess.C41,
            Exists,
            NextId);
        Check(again.Rows.Count == 1, "import_skips_existing_file");
        Check(
            again.Rejected[0].Refusal == FrameImportRefusal.AlreadyInLibrary,
            "import_reports_duplicate");
        Check(
            again.Rows[0].Payload["scanIndex"]!.GetValue<int>() == 1,
            "import_continues_scan_index");

        // 같은 호출 안에서 같은 파일을 두 번 고른 경우도 한 건입니다.
        FrameImportPlan twice = FrameImport.Plan(
            [@"C:\scans\d.tif", @"C:\scans\d.tif"],
            [],
            DevelopmentProcess.C41,
            Exists,
            NextId);
        Check(twice.Rows.Count == 1, "import_deduplicates_within_one_call");

        FrameImportPlan bad = FrameImport.Plan(
            [@"scans\relative.tif", @"C:\scans\missing.tif"],
            [],
            DevelopmentProcess.C41,
            Exists,
            NextId);
        Check(bad.Rows.Count == 0, "import_rejects_bad_paths");
        Check(
            bad.Rejected[0].Refusal == FrameImportRefusal.InvalidPath,
            "import_rejects_relative_path");
        Check(
            bad.Rejected[1].Refusal == FrameImportRefusal.FileNotFound,
            "import_rejects_missing_file");

        Check(
            FrameImport.Plan([], [], DevelopmentProcess.C41, Exists, NextId)
                .Rejected[0].Refusal == FrameImportRefusal.NoFiles,
            "import_empty_selection");

        // 고른 것 중 일부만 들어왔는데 아무 말이 없으면 나머지가 어디 갔는지 알 수 없습니다.
        Check(
            FrameImport.Describe(plan).Contains("Imported 2 frames"),
            "import_describe_count");
        Check(
            FrameImport.Describe(plan).Contains("Dmin"),
            "import_describe_says_next_step");
        Check(
            FrameImport.Describe(again).Contains("skipped"),
            "import_describe_mentions_skipped");
        Check(
            FrameImport.Describe(bad).Contains("Nothing imported"),
            "import_describe_nothing");

        ScannerFrameImport scanner = new(
            @"C:\scans\scan-01.tif",
            @"C:\scans\scan-01.ir.tif",
            DevelopmentProcess.C41);
        FrameImportPlan scannerPlan = FrameImport.PlanScanner(
            scanner,
            [],
            Exists,
            NextId);
        Check(scannerPlan.Rows.Count == 1 && scannerPlan.Rejected.Count == 0,
            "scanner_publish_plans_paired_artifacts");
        Check(
            scannerPlan.Rows[0].Payload["sourceKind"]!.GetValue<string>() == "scanner" &&
            scannerPlan.Rows[0].Payload["infraredScanPath"]!.GetValue<string>() ==
                @"C:\scans\scan-01.ir.tif",
            "scanner_publish_records_infrared_companion");
        Check(
            ReadImported(scannerPlan.Rows[0].Payload).Frame?.InfraredPath ==
                @"C:\scans\scan-01.ir.tif",
            "scanner_publish_companion_survives_catalog_projection");
        Check(
            FrameImport.PlanScanner(
                scanner with { InfraredPath = @"C:\scans\scan-01.tif" },
                [],
                Exists,
                NextId).Rejected[0].Refusal == FrameImportRefusal.InfraredMatchesVisible,
            "scanner_publish_rejects_same_rgb_ir_artifact");
        Check(
            FrameImport.PlanScanner(
                scanner with { InfraredPath = @"C:\scans\missing.ir.tif" },
                [],
                Exists,
                NextId).Rejected[0].Refusal == FrameImportRefusal.InfraredFileNotFound,
            "scanner_publish_rejects_missing_ir_artifact");
    }

    private static void VerifyFolderImport()
    {
        string testParent = Path.Combine(AppContext.BaseDirectory, "folder-import-tests");
        string isolatedBase = Path.Combine(testParent, $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        string source = Path.Combine(isolatedBase, "source");
        string empty = Path.Combine(isolatedBase, "empty");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;

        try
        {
            Directory.CreateDirectory(source);
            Directory.CreateDirectory(empty);
            File.WriteAllBytes(Path.Combine(source, "B.tiff"), [0]);
            File.WriteAllBytes(Path.Combine(source, "A.tif"), [0]);
            File.WriteAllBytes(Path.Combine(source, "C.jpg"), [0]);
            File.WriteAllBytes(Path.Combine(source, "D.dng"), [0]);
            File.WriteAllBytes(Path.Combine(source, "E.arw"), [0]);
            File.WriteAllBytes(Path.Combine(source, "ignore.txt"), [0]);

            FakeDispatcher dispatcher = new(accepts: true);
            FakeExporter exporter = new(_ => OkResult());
            using (LibraryHostService host = new(dispatcher, exporter, TestSourceMetadata))
            {
                Check(host.Open(roots) == LibraryHostState.Open, "folder_import_host_open");
                FolderImportResult imported = host.ImportFolders([source], DevelopmentProcess.C41);
                Check(imported.IsSuccess && imported.AddedFolderCount == 1 &&
                      imported.AddedFrameCount == 5 && imported.Plan.Rejected.Count == 0,
                    "folder_import_registers_folder_standard_and_raw_images_atomically");
                Check(host.Folders.Single().SourcePath == Path.GetFullPath(source) &&
                      string.Join(',', host.Frames.Select(frame => frame.DisplayName)) ==
                          "A.tif,B.tiff,C.jpg,D.dng,E.arw",
                    "folder_import_preserves_standard_and_raw_file_order");

                FolderImportResult emptyImport = host.ImportFolders([empty], DevelopmentProcess.C41);
                Check(emptyImport.IsSuccess && emptyImport.AddedFolderCount == 1 &&
                      emptyImport.AddedFrameCount == 0 && host.Folders.Count == 2,
                    "folder_import_keeps_empty_folder_as_library_source");
            }

            using LibraryHostService reopened = new(new FakeDispatcher(accepts: true), new FakeExporter(_ => OkResult()));
            Check(reopened.Open(roots) == LibraryHostState.Open && reopened.Folders.Count == 2 &&
                  reopened.Frames.Count == 5,
                "folder_import_persists_folders_and_frames_together");
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

    private static LibraryFrameReadResult ReadImported(JsonObject record)
    {
        using JsonDocument document = JsonDocument.Parse(
            CatalogJson.SerializeCanonical(record));
        return LibraryFrameReader.Read(document.RootElement);
    }

    // The part that has to be right is *what gets measured*: a neutral develop. Measuring
    // the frame as it stands would fold the existing correction into the answer and make
    // every press drift further.
}
