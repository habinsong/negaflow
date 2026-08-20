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

internal static class LibraryHostTests
{
    public static void Run()
    {
        VerifyLibraryHost();
        VerifyLibraryAvailability();
        VerifyLibraryBrowserProjection();
    }

    private static void VerifyLibraryHost()
    {
        string testParent = Path.Combine(AppContext.BaseDirectory, "library-host-tests");
        string isolatedBase = Path.Combine(
            testParent,
            $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;
        FakeDispatcher dispatcher = new(accepts: true);
        FakeExporter exporter = new(_ => OkResult());

        try
        {
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
                            ],
                        })).IsSuccess,
                    "library_host_seed");
            }

            using LibraryHostService host = new(dispatcher, exporter, TestSourceMetadata);
            Check(host.State == LibraryHostState.NotOpened, "library_host_starts_unopened");
            Check(host.Frames.Count == 0, "library_host_no_frames_before_open");

            Check(host.Open(roots) == LibraryHostState.Open, "library_host_open");
            Check(host.Frames.Count == 1, "library_host_loads_frames");
            Check(host.RestoreActiveFrame("frame-1") == "frame-1" &&
                host.ActiveFrameId == "frame-1" &&
                host.SelectedFrameIds.SequenceEqual(["frame-1"]),
                "library_host_restores_shared_active_frame");

            string oldRelinkPath = Path.Combine(isolatedBase, "missing", "relink-source.tif");
            string newRelinkPath = Path.Combine(isolatedBase, "recovered", "relink-source.tif");
            Directory.CreateDirectory(Path.GetDirectoryName(oldRelinkPath)!);
            Directory.CreateDirectory(Path.GetDirectoryName(newRelinkPath)!);
            File.WriteAllBytes(oldRelinkPath, [4, 5, 6]);
            Check(host.Import([oldRelinkPath], DevelopmentProcess.C41).Rows.Count == 1,
                "library_relink_imports_source");
            Check(host.ActiveFrameId == host.Frames[^1].Id &&
                host.SelectedFrameIds.SequenceEqual([host.Frames[^1].Id]),
                "library_import_selects_the_newest_frame_for_develop");
            string incompatibleRelinkPath = Path.Combine(
                isolatedBase, "recovered", "incompatible-source.tif");
            File.WriteAllBytes(incompatibleRelinkPath, [9, 9, 9]);
            SourceRelinkPlan? incompatibleRelink = SourceRelinkPlanner.FilePlan(
                oldRelinkPath,
                incompatibleRelinkPath);
            Check(
                incompatibleRelink is not null &&
                host.Relink(incompatibleRelink).UpdatedFrameCount == 0 &&
                host.Frames.Any(frame => frame.SourcePath == oldRelinkPath),
                "library_relink_refuses_incompatible_tiff_metadata");
            File.Move(oldRelinkPath, newRelinkPath);
            SourceRelinkPlan? directRelink = SourceRelinkPlanner.FilePlan(
                oldRelinkPath,
                newRelinkPath);
            Check(directRelink is not null, "library_relink_builds_direct_plan");
            LibrarySourceRelinkResult relink = host.Relink(directRelink!);
            Check(relink.IsSuccess && relink.UpdatedFrameCount == 1 &&
                host.Frames.Any(frame => frame.SourcePath == newRelinkPath),
                "library_relink_updates_catalog_source_atomically");
            SourceRelinkPlan folderRelink = SourceRelinkPlanner.FolderPlan(
                Path.Combine(isolatedBase, "missing"),
                Path.Combine(isolatedBase, "recovered"),
                [Frame(new ManualBaseRgb(0.2, 0.2, 0.2), sourcePath: oldRelinkPath)],
                path => path == newRelinkPath);
            Check(folderRelink.Mappings.Any(mapping => mapping.NewSourcePath == newRelinkPath),
                "library_relink_preserves_relative_folder_path");

            string oldFolderRoot = Path.Combine(isolatedBase, "folder-old");
            string newFolderRoot = Path.Combine(isolatedBase, "folder-new");
            string oldFolderFrame = Path.Combine(oldFolderRoot, "folder-frame.tif");
            Directory.CreateDirectory(oldFolderRoot);
            File.WriteAllBytes(oldFolderFrame, [7, 8, 9]);
            Check(host.ImportFolders([oldFolderRoot], DevelopmentProcess.C41).IsSuccess,
                "library_folder_relink_imports_registered_folder");
            string folderId = host.Folders.Single(folder => folder.SourcePath == oldFolderRoot).Id;
            Directory.Move(oldFolderRoot, newFolderRoot);
            SourceRelinkPlan completeFolderRelink = SourceRelinkPlanner.FolderPlan(
                oldFolderRoot,
                newFolderRoot,
                host.Frames);
            LibrarySourceRelinkResult folderResult = host.Relink(completeFolderRelink);
            Check(
                folderResult.IsSuccess && folderResult.UpdatedFrameCount == 1 &&
                host.Folders.Single(folder => folder.Id == folderId).SourcePath == newFolderRoot &&
                host.Frames.Any(frame => frame.SourcePath == Path.Combine(newFolderRoot, "folder-frame.tif")),
                "library_folder_relink_updates_frame_and_registered_folder_atomically");

            // Scanner host는 artifact transaction을 끝낸 RGB/IR 쌍만 여기로 넘긴다. catalog
            // publication이 먼저 성공하고, IR decode 실패는 frame 자체를 되돌리거나 지우지 않는다.
            string scannedRgb = Path.Combine(isolatedBase, "published-rgb.tif");
            string scannedInfrared = Path.Combine(isolatedBase, "published-ir.tif");
            File.WriteAllBytes(scannedRgb, [1, 2, 3, 4]);
            File.WriteAllBytes(scannedInfrared, [5, 6, 7, 8]);
            ScannerFramePublishResult published = host.PublishScannerFrame(
                new ScannerFrameImport(scannedRgb, scannedInfrared, DevelopmentProcess.C41));
            Check(published.Plan.Rows.Count == 1 && published.Frame is not null,
                "scanner_publish_adds_frame_before_ir_detection");
            Check(
                published.Frame?.InfraredPath == scannedInfrared &&
                published.Infrared?.Status == InfraredDefectApplyStatus.DetectionFailed,
                "scanner_publish_keeps_pair_when_ir_decode_fails");
            Check(host.Frames.Any(frame => frame.Id == published.Frame?.Id),
                "scanner_publish_projects_durable_frame");
            Check(ScannerPublicationReceiptStore.ReadPending(roots).Count == 0,
                "scanner_publish_completes_recovery_receipt_after_catalog_commit");

            IReadOnlyList<LibraryFrameListItem> items =
                LibraryFrameListItems.From(host.Frames);
            // macOS 는 스캐너 프레임을 파일 이름이 아니라 번호로 부릅니다.
            Check(items[0].DisplayName == "Frame 1", "library_item_display_name");
            Check(items[0].CanDevelop, "library_item_can_develop");
            Check(items[0].Detail == @"C:\scans\IMG_0001.tif", "library_item_detail_is_path");
            IReadOnlyList<LibraryFrameListItem> phraseMatches = LibraryFrameListItems.Filter(
                [
                    new LibraryFrameListItem(Frame(
                        new ManualBaseRgb(0.2, 0.2, 0.2),
                        displayName: "사진 3",
                        sourcePath: @"C:\scans\L1000003.tif")),
                    new LibraryFrameListItem(Frame(
                        new ManualBaseRgb(0.2, 0.2, 0.2),
                        displayName: "사진1",
                        sourcePath: @"C:\scans\L1000001.tif")),
                    new LibraryFrameListItem(Frame(
                        new ManualBaseRgb(0.2, 0.2, 0.2),
                        displayName: "Kodak Portra 400",
                        sourcePath: @"C:\scans\film.tif")),
                ],
                "사진 1");
            Check(phraseMatches.Count == 1 && phraseMatches[0].DisplayName == "사진1",
                "library_item_phrase_search_does_not_cross_values");
            Check(
                LibraryFrameListItems.Filter(phraseMatches, "portra400").Count == 0 &&
                LibraryFrameListItems.Filter(
                    [new LibraryFrameListItem(Frame(new ManualBaseRgb(0.2, 0.2, 0.2),
                        displayName: "Kodak Portra 400"))], "portra400").Count == 1,
                "library_item_phrase_search_ignores_whitespace");
            Check(
                LibraryFrameListItems.IssueSummary(host.Issues) is null,
                "library_item_no_issue_summary");

            // 현상할 수 없는 frame 은 목록에서 그 이유가 보입니다. Export 가 조용히 아무것도
            // 하지 않는 것보다 낫습니다.
            LibraryFrameListItem noBase = new(Frame(
                null,
                baseRecipe: new BaseRecipe(BaseEstimationMode.Manual, null, null, null)));
            Check(!noBase.CanDevelop, "library_item_cannot_develop");
            Check(noBase.Detail == "Dmin not set", "library_item_shows_reason");

            LibraryFrameListItem preset = new(Frame(
                new ManualBaseRgb(0.2, 0.2, 0.2),
                baseRecipe: new BaseRecipe(BaseEstimationMode.Preset, "kodak-portra-400", null, null)));
            Check(preset.CanDevelop, "library_item_preset_can_develop");
            Check(
                preset.Detail == @"C:\scans\IMG_0001.tif",
                "library_item_shows_preset_source");

            LibraryFrameListItem positive = new(Frame(
                null,
                SourceSignalKind.FilmPositiveScan,
                FilmType.ColorPositive));
            Check(positive.CanDevelop, "library_item_positive_can_develop");
            Check(
                positive.Detail == @"C:\scans\IMG_0001.tif",
                "library_item_positive_shows_source");

            LibraryFrameListItem digital = new(Frame(
                null,
                SourceSignalKind.RenderedDigital,
                FilmType.ColorPositive));
            Check(digital.CanDevelop, "library_item_rendered_digital_can_develop");
            Check(
                digital.Detail == @"C:\scans\IMG_0001.tif",
                "library_item_rendered_digital_shows_source");

            Check(
                LibraryFrameListItems.IssueSummary(
                    [new LibraryFrameIssue(2, "frame-3", LibraryFrameError.MissingSourcePath,
                        DevelopRouteError.None)])?.Contains("still in the catalog") == true,
                "library_item_issue_summary_says_data_is_kept");

            Check(
                host.Edit("frame-1", new LibraryFrameEdit(
                    new ToneAdjustment(0.75, 0, 0, 0, 0, 0),
                    new ManualBaseRgb(0.21, 0.22, 0.23))) == LibraryFrameError.None,
                "library_host_edit");
            Check(host.Save() == CatalogStoreError.None, "library_host_save");

            DevelopExportOutcome? outcome = null;
            Check(
                host.ExportAsync(
                    host.Frames[0],
                    @"C:\exports\IMG_0001.png",
                    DevelopExportFormat.Png16,
                    completed => outcome = completed).GetAwaiter().GetResult(),
                "library_host_export_delivers");
            Check(
                outcome?.Kind == DevelopExportOutcomeKind.Completed,
                "library_host_export_completed");
            Check(exporter.CallCount == 1, "library_host_export_called_engine");
            Check(!host.IsExporting, "library_host_export_flag_clears");
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

    private static void VerifyLibraryAvailability()
    {
        int fileProbes = 0;
        LibraryAvailabilitySnapshot snapshot = LibraryAvailability.Probe(
            [
                Frame(new ManualBaseRgb(0.2, 0.2, 0.2), sourcePath: @"C:\scans\online.tif") with { Id = "online" },
                Frame(new ManualBaseRgb(0.2, 0.2, 0.2), sourcePath: @"C:\scans\offline.tif") with { Id = "offline" },
                Frame(new ManualBaseRgb(0.2, 0.2, 0.2), sourcePath: @"C:\scans\online.tif") with { Id = "online-copy" },
            ],
            [
                new LibraryFolderSnapshot("folder-online", @"C:\scans", DateTimeOffset.UnixEpoch),
                new LibraryFolderSnapshot("folder-offline", @"C:\missing", DateTimeOffset.UnixEpoch),
            ],
            path =>
            {
                ++fileProbes;
                return path.EndsWith("online.tif", StringComparison.OrdinalIgnoreCase);
            },
            path => path == @"C:\scans");

        Check(
            fileProbes == 2 &&
            snapshot.ByFrameId["online"] == LibrarySourceAvailability.Online &&
            snapshot.ByFrameId["offline"] == LibrarySourceAvailability.Offline &&
            snapshot.ByFrameId["online-copy"] == LibrarySourceAvailability.Online,
            "library_availability_deduplicates_source_paths");
        Check(
            snapshot.ByFolderId["folder-online"] && !snapshot.ByFolderId["folder-offline"],
            "library_availability_records_folder_status");
    }

    private static void VerifyLibraryBrowserProjection()
    {
        IReadOnlyList<LibraryFrameListItem> items = LibraryFrameListItems.From(
            [
                Frame(new ManualBaseRgb(0.2, 0.2, 0.2), sourcePath: @"C:\library\A\one.tif") with { Id = "one" },
                Frame(null, SourceSignalKind.FilmPositiveScan, FilmType.ColorPositive,
                    sourcePath: @"C:\library\B\two.tif") with { Id = "two" },
                Frame(new ManualBaseRgb(0.2, 0.2, 0.2), sourcePath: @"C:\library\A\three.tif") with { Id = "three" },
                Frame(new ManualBaseRgb(0.2, 0.2, 0.2), sourcePath: @"C:\library\A\ignored.tif") with { Id = "one" },
            ],
            new Dictionary<string, LibrarySourceAvailability>
            {
                ["one"] = LibrarySourceAvailability.Online,
                ["two"] = LibrarySourceAvailability.Offline,
                ["three"] = LibrarySourceAvailability.Online,
            });
        IReadOnlyList<LibraryFolderSnapshot> folders =
        [
            new("folder-a", @"C:\library\A", DateTimeOffset.UnixEpoch),
            new("folder-empty", @"C:\library\Empty", DateTimeOffset.UnixEpoch),
        ];
        Dictionary<string, bool> availability = new()
        {
            ["folder-a"] = true,
            ["folder-empty"] = false,
        };

        LibraryBrowserProjection foldersProjection = LibraryBrowserProjector.Create(
            items, folders, availability, LibraryBrowserViewMode.Folders);
        Check(
            foldersProjection.SourceCount == 3 && foldersProjection.MatchedCount == 3 &&
            foldersProjection.FolderSections.Count == 3 &&
            foldersProjection.FolderSections[0].Items.Select(item => item.Id).SequenceEqual(["one", "three"]) &&
            foldersProjection.FolderSections[1].Items.Count == 0 &&
            foldersProjection.FolderSections[1].IsRegistered &&
            foldersProjection.FolderSections[2].Items.Single().Id == "two",
            "library_browser_folders_keeps_registered_empty_and_implicit_sections");

        LibraryBrowserProjection filmProjection = LibraryBrowserProjector.Create(
            items, folders, availability, LibraryBrowserViewMode.FilmType, FilmType.ColorPositive);
        Check(
            filmProjection.MatchedCount == 1 && filmProjection.FolderSections.Count == 1 &&
            filmProjection.FolderSections.Single().Items.Single().Id == "two",
            "library_browser_film_type_filters_before_grouping");

        LibraryBrowserProjection offlineProjection = LibraryBrowserProjector.Create(
            items, folders, availability, LibraryBrowserViewMode.Offline);
        Check(
            offlineProjection.Items.Single().Id == "two" && offlineProjection.FolderSections.Count == 0,
            "library_browser_offline_uses_availability_snapshot");

        RunFolderDevelopmentDrafts(items, folders, availability);
    }

    /// <summary>
    /// 폴더 머리줄에서 고른 프로세스·타깃은 <b>적용을 누르기 전까지</b> 살아 있어야 합니다.
    ///
    /// ☠️ 예전에는 고르개가 프레임의 **현재** 값에 묶여 있어, 썸네일 한 장만 도착해 격자가 다시
    ///    투영돼도 고른 값이 되돌아갔습니다 — 사용자에게는 "고르고 적용을 눌러도 아무 일이
    ///    없다" 로 보입니다. macOS 는 그 값을 컨트롤의 `@State` 로 들고 프레임이 실제로 달라질
    ///    때만 다시 맞춥니다(`onChange(of: referenceSelection)`).
    /// </summary>
    private static void RunFolderDevelopmentDrafts(
        IReadOnlyList<LibraryFrameListItem> items,
        IReadOnlyList<LibraryFolderSnapshot> folders,
        IReadOnlyDictionary<string, bool> availability)
    {
        LibraryFolderDevelopmentDrafts drafts = new();
        LibraryBrowserProjection first = LibraryBrowserProjector.Create(
            items, folders, availability, LibraryBrowserViewMode.Folders, FilmType.ColorNegative, drafts);
        LibraryBrowserFolderSection section = first.FolderSections[0];
        (DevelopmentProcess beforeProcess, DevelopTarget beforeTarget) = section.Selection;
        Check(beforeTarget == DevelopTarget.Main, "folder_draft_starts_at_frame_value");

        // macOS `.padding(6).padding(.top, isFirst ? 0 : 16)` — 첫 폴더만 위가 붙습니다.
        Check(section.IsFirst && section.HeaderMargin == "6", "folder_header_first_has_no_top_gap");
        Check(
            first.FolderSections.Skip(1).All(other => !other.IsFirst && other.HeaderMargin == "6,22,6,6"),
            "folder_header_later_folders_keep_the_16_gap");

        drafts.SetTarget(section.Id, DevelopTarget.Hr, beforeProcess, beforeTarget);
        drafts.SetProcess(section.Id, DevelopmentProcess.E6, beforeProcess, beforeTarget);

        // 격자를 다시 투영합니다 — 썸네일 도착·선택 변경 등으로 실제로 매번 일어나는 일입니다.
        LibraryBrowserProjection second = LibraryBrowserProjector.Create(
            items, folders, availability, LibraryBrowserViewMode.Folders, FilmType.ColorNegative, drafts);
        LibraryBrowserFolderSection reprojected = second.FolderSections[0];
        (DevelopmentProcess keptProcess, DevelopTarget keptTarget) = reprojected.Selection;
        Check(
            keptTarget == DevelopTarget.Hr && keptProcess == DevelopmentProcess.E6,
            "folder_draft_survives_reprojection");
        Check(
            reprojected.TargetChoices[reprojected.TargetIndex].Target == DevelopTarget.Hr,
            "folder_draft_drives_the_target_picker");
        Check(
            reprojected.ProcessChoices[reprojected.ProcessIndex].Process == DevelopmentProcess.E6,
            "folder_draft_drives_the_process_picker");

        // 프레임이 실제로 다른 값이 되면 macOS 처럼 초안을 버리고 새 값을 보입니다.
        (DevelopmentProcess resolvedProcess, DevelopTarget resolvedTarget) =
            drafts.Resolve(section.Id, DevelopmentProcess.D76, DevelopTarget.Sp3000);
        Check(
            resolvedProcess == DevelopmentProcess.D76 && resolvedTarget == DevelopTarget.Sp3000,
            "folder_draft_yields_when_the_frame_actually_changed");

        drafts.SetTarget(section.Id, DevelopTarget.F135, beforeProcess, beforeTarget);
        drafts.Clear(section.Id);
        Check(
            drafts.Resolve(section.Id, beforeProcess, beforeTarget) == (beforeProcess, beforeTarget),
            "folder_draft_clears_after_apply");
    }

}
