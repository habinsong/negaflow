using System.Text.Json;
using System.Text.Json.Nodes;
using System.Collections.Concurrent;
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
        // macOS 는 가져오기에서 `customDisplayName` 을 쓰지 않습니다 — 이름은 확장자를 뗀 파일
        // 이름에서 파생합니다(`sourceFileBaseName`).
        //
        // 예전에는 `Path.GetFileName` 을 그대로 적어 카드·필름스트립·창 제목이 `a.tif` 가
        // 되고 내보내기 파일명이 `a.tif.jpg` 로 나왔습니다.
        Check(
            !plan.Rows[0].Payload.ContainsKey("customDisplayName"),
            "import_leaves_display_name_to_the_file_name");
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
                _ => null).Rejected.Single().Refusal == FrameImportRefusal.UndecodableImage,
            "import_rejects_unprobed_source");
        int unsupportedMetadataReads = 0;
        Check(
            FrameImport.Plan(
                [@"C:\scans\vector.svg"],
                [],
                DevelopmentProcess.C41,
                Exists,
                NextId,
                _ =>
                {
                    ++unsupportedMetadataReads;
                    return new LibrarySourceMetadata(4096, 64, 32, 3, 16, 1, 1);
                }).Rejected.Single().Refusal == FrameImportRefusal.UnsupportedImage &&
            unsupportedMetadataReads == 0,
            "import_rejects_svg_before_metadata_decode");
        Check(
            FrameImport.Plan(
                [@"C:\scans\future-camera-format.xyzraw"],
                [],
                DevelopmentProcess.C41,
                Exists,
                NextId,
                _ => new LibrarySourceMetadata(4096, 64, 32, 3, 16, 1, 1))
                .Rows.Count == 1,
            "import_accepts_decoder_supported_format_without_extension_allowlist");
        Check(
            FrameImport.Plan(
                [@"C:\scans\not-an-image.txt"],
                [],
                DevelopmentProcess.C41,
                Exists,
                NextId,
                _ => null).Rejected.Single().Refusal == FrameImportRefusal.UndecodableImage,
            "import_rejects_non_image_by_decoder_probe");

        // SVG 계약 거부와 "디코더가 못 읽음" 은 사용자 대처가 다릅니다. SVG 는 무엇을 설치해도
        // 열리지 않고, 후자는 파일이 깨졌거나 그 카메라를 아직 지원하지 않는 것입니다.
        // 한 값으로 합치면 안내가 뒤섞이므로 서로 다른 사유로 남는지 못 박습니다.
        Check(
            FrameImport.Describe(FrameImport.Plan(
                [@"C:\scans\vector.svg"],
                [],
                DevelopmentProcess.C41,
                Exists,
                NextId,
                _ => null)).Contains("vector", StringComparison.Ordinal),
            "svg_refusal_says_vector_not_tiff");
        Check(
            FrameImport.Describe(FrameImport.Plan(
                [@"C:\scans\broken.cr3"],
                [],
                DevelopmentProcess.C41,
                Exists,
                NextId,
                _ => null)).Contains("no available decoder", StringComparison.Ordinal),
            "undecodable_refusal_does_not_claim_tiff");

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
        int duplicateMetadataReads = 0;
        FrameImportPlan duplicateWithMetadataReader = FrameImport.Plan(
            [@"C:\scans\a.tif"],
            [existing],
            DevelopmentProcess.C41,
            Exists,
            NextId,
            _ =>
            {
                ++duplicateMetadataReads;
                return new LibrarySourceMetadata(4096, 64, 32, 3, 16, 1, 1);
            });
        Check(
            duplicateWithMetadataReader.Rejected.Single().Refusal ==
                FrameImportRefusal.AlreadyInLibrary &&
            duplicateMetadataReads == 0,
            "import_skips_duplicate_metadata_decode");

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
        string nonLeaf = Path.Combine(isolatedBase, "non-leaf");
        string child = Path.Combine(nonLeaf, "child");
        string parentOnly = Path.Combine(isolatedBase, "parent-only");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;

        try
        {
            Directory.CreateDirectory(source);
            Directory.CreateDirectory(empty);
            Directory.CreateDirectory(child);
            Directory.CreateDirectory(Path.Combine(parentOnly, "nested"));
            File.WriteAllBytes(Path.Combine(source, "B.tiff"), [0]);
            File.WriteAllBytes(Path.Combine(source, "A.tif"), [0]);
            File.WriteAllBytes(Path.Combine(source, "C.jpg"), [0]);
            File.WriteAllBytes(Path.Combine(source, "D.dng"), [0]);
            File.WriteAllBytes(Path.Combine(source, "E.arw"), [0]);
            File.WriteAllBytes(Path.Combine(source, "ignore.txt"), [0]);
            File.WriteAllBytes(Path.Combine(nonLeaf, "visible.tiff"), [0]);
            File.WriteAllBytes(Path.Combine(child, "nested.tiff"), [0]);

            FakeDispatcher dispatcher = new(accepts: true);
            FakeExporter exporter = new(_ => OkResult());
            LibrarySourceMetadata? DecodeImage(string path) =>
                string.Equals(Path.GetExtension(path), ".txt", StringComparison.OrdinalIgnoreCase)
                    ? null
                    : TestSourceMetadata(path);
            using (LibraryHostService host = new(dispatcher, exporter, DecodeImage))
            {
                Check(host.Open(roots) == LibraryHostState.Open, "folder_import_host_open");
                FolderImportResult imported = host.ImportFolders([source], DevelopmentProcess.C41);
                Check(imported.IsSuccess && imported.AddedFolderCount == 1 &&
                      imported.AddedFrameCount == 5 && imported.Plan.Rejected.Count == 0,
                    "folder_import_registers_folder_standard_and_raw_images_atomically");
                Check(host.Folders.Single().SourcePath == Path.GetFullPath(source) &&
                      string.Join(',', host.Frames.Select(frame => frame.EffectiveDisplayName)) ==
                          "A,B,C,D,E",
                    "folder_import_preserves_standard_and_raw_file_order");

                using var contentChanged = new AutoResetEvent(false);
                var changedEvents = new ConcurrentQueue<LibraryContentChangedEventArgs>();
                host.LibraryContentChanged += (_, args) =>
                {
                    changedEvents.Enqueue(args);
                    contentChanged.Set();
                };
                string selectedBeforeSync = host.ActiveFrameId!;
                string addedPath = Path.Combine(source, "F.tif");
                File.WriteAllBytes(addedPath, [0]);
                Check(contentChanged.WaitOne(TimeSpan.FromSeconds(5)) &&
                      host.Frames.Count == 6 && host.ActiveFrameId == selectedBeforeSync,
                    "folder_monitor_adds_new_image_without_stealing_selection");

                LibraryFrameSnapshot addedFrame = host.Frames.Single(frame =>
                    string.Equals(frame.SourcePath, addedPath, StringComparison.OrdinalIgnoreCase));
                string renamedPath = Path.Combine(source, "G.tif");
                File.Move(addedPath, renamedPath);
                Check(contentChanged.WaitOne(TimeSpan.FromSeconds(5)) &&
                      host.Frames.Any(frame => frame.Id == addedFrame.Id &&
                          string.Equals(frame.SourcePath, renamedPath,
                              StringComparison.OrdinalIgnoreCase)),
                    "folder_monitor_rename_preserves_frame_identity_and_edits");

                string aPath = Path.Combine(source, "A.tif");
                string aFrameId = host.Frames.Single(frame =>
                    string.Equals(frame.SourcePath, aPath, StringComparison.OrdinalIgnoreCase)).Id;
                string infraredPath = Path.Combine(source, "A.ir.tif");
                File.WriteAllBytes(infraredPath, [0]);
                Check(contentChanged.WaitOne(TimeSpan.FromSeconds(5)) &&
                      host.Frames.Count == 6 &&
                      string.Equals(
                          host.Frames.Single(frame => frame.Id == aFrameId).InfraredPath,
                          infraredPath,
                          StringComparison.OrdinalIgnoreCase),
                    "folder_monitor_attaches_ir_without_publishing_an_ir_frame");

                string renamedInfraredPath = Path.Combine(source, "A_ir.tif");
                File.Move(infraredPath, renamedInfraredPath);
                Check(contentChanged.WaitOne(TimeSpan.FromSeconds(5)) &&
                      string.Equals(
                          host.Frames.Single(frame => frame.Id == aFrameId).InfraredPath,
                          renamedInfraredPath,
                          StringComparison.OrdinalIgnoreCase),
                    "folder_monitor_relinks_ir_companion_without_a_visible_row");

                File.WriteAllBytes(Path.Combine(source, "B.tiff"), [1]);
                Check(contentChanged.WaitOne(TimeSpan.FromSeconds(5)) &&
                      changedEvents.Any(args => args.InvalidatedFrameIds.Any(id =>
                          host.Frames.Any(frame => frame.Id == id &&
                              string.Equals(frame.SourcePath, Path.Combine(source, "B.tiff"),
                                  StringComparison.OrdinalIgnoreCase)))),
                    "folder_monitor_invalidates_replaced_source_caches");

                File.Delete(renamedInfraredPath);
                File.Delete(renamedPath);
                Check(contentChanged.WaitOne(TimeSpan.FromSeconds(5)) &&
                      host.Frames.Count == 5 &&
                      host.Frames.Single(frame => frame.Id == aFrameId).InfraredPath is null,
                    "folder_monitor_removes_deleted_source_and_detaches_deleted_ir");

                string laterChild = Path.Combine(source, "later-child");
                string blockedImage = Path.Combine(source, "H.tif");
                Directory.CreateDirectory(laterChild);
                File.WriteAllBytes(blockedImage, [0]);
                Thread.Sleep(TimeSpan.FromMilliseconds(1_200));
                Check(host.Frames.Count == 5 && !host.Frames.Any(frame =>
                        string.Equals(frame.SourcePath, blockedImage,
                            StringComparison.OrdinalIgnoreCase)),
                    "folder_monitor_fails_closed_when_registered_folder_stops_being_leaf");
                Directory.Delete(laterChild);
                Check(contentChanged.WaitOne(TimeSpan.FromSeconds(5)) &&
                      host.Frames.Any(frame => string.Equals(
                          frame.SourcePath,
                          blockedImage,
                          StringComparison.OrdinalIgnoreCase)),
                    "folder_monitor_recovers_leaf_and_imports_pending_image_once");
                File.Delete(blockedImage);
                Check(contentChanged.WaitOne(TimeSpan.FromSeconds(5)) && host.Frames.Count == 5,
                    "folder_monitor_returns_to_exact_file_set_after_delete");

                FolderImportResult emptyImport = host.ImportFolders([empty], DevelopmentProcess.C41);
                Check(!emptyImport.IsSuccess && emptyImport.AddedFolderCount == 0 &&
                      emptyImport.AddedFrameCount == 0 && host.Folders.Count == 1 &&
                      emptyImport.Plan.Rejected.Single().Refusal ==
                          FolderImportRefusal.NoImportableImages,
                    "folder_import_rejects_empty_leaf");

                FolderImportResult mixedParent = host.ImportFolders(
                    [nonLeaf],
                    DevelopmentProcess.C41);
                FolderImportResult childOnlyParent = host.ImportFolders(
                    [parentOnly],
                    DevelopmentProcess.C41);
                Check(!mixedParent.IsSuccess && !childOnlyParent.IsSuccess &&
                      mixedParent.Plan.Rejected.Single().Refusal ==
                          FolderImportRefusal.HasSubfolders &&
                      childOnlyParent.Plan.Rejected.Single().Refusal ==
                          FolderImportRefusal.HasSubfolders &&
                      host.Folders.Count == 1 && host.Frames.Count == 5,
                    "folder_import_rejects_every_non_leaf_without_recursive_import");
            }

            using LibraryHostService reopened = new(new FakeDispatcher(accepts: true), new FakeExporter(_ => OkResult()));
            Check(reopened.Open(roots) == LibraryHostState.Open && reopened.Folders.Count == 1 &&
                  reopened.Frames.Count == 5,
                "folder_import_persists_only_the_image_leaf");
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
