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

internal static class LibraryOrganizationTests
{
    public static void Run()
    {
        VerifyLibraryCollections();
        VerifyLibraryRolls();
        VerifyExportRecipes();
    }

    private static void VerifyLibraryCollections()
    {
        string parent = Path.Combine(AppContext.BaseDirectory, "collection-tests");
        string isolatedBase = Path.Combine(parent, $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;
        string frameId = Guid.NewGuid().ToString("D");
        try
        {
        using (CatalogSession session = CatalogSession.Open(roots).Session!)
        {
            Check(session.ReadOrCreate().IsSuccess, "collections_catalog_create");
            Check(session.Write(new CatalogSnapshot(
                null,
                new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
                {
                    [CatalogEntityTable.Frames] =
                    [new CatalogEntityRow(frameId, FrameRecord(frameId, "C_0001.tif", 0))],
                })).IsSuccess, "collections_catalog_seed");
        }
        LibraryDocumentOpenResult opened = LibraryDocument.Open(roots);
        if (opened.Document is not { } document)
        {
            Check(false, "collections_open_document");
            return;
        }

        using (document)
        {
            Check(
                document.CreateCollection("   ", []) is null,
                "collections_refuse_an_empty_name");

            string? id = document.CreateCollection(
                "  Roll 01  ",
                [frameId, frameId, "not-in-the-catalog"]);
            Check(id is not null, "collections_create");
            Check(document.Collections.Count == 1, "collections_projected");
            Check(document.Collections[0].Name == "Roll 01", "collections_trim_the_name");
            // 없는 id 와 중복은 버립니다. 카탈로그에 있는 frame 하나만 남습니다.
            Check(
                document.Collections[0].FrameIds.Count == 1,
                "collections_keep_only_known_frames");

            // 저장된 찾기는 조건 본문을 카탈로그 구조와 분리해 담습니다.
            LibraryQuickFilterState filters = new()
            {
                MinimumRating = 4,
                Picked = true,
                Infrared = true,
            };
            LibraryStoredQuery query = LibraryStoredQuery.From(filters, "  bukhansan  ");
            Check(query.SearchText == "bukhansan", "stored_query_trims_the_search");
            Check(
                document.CreateStoredSearch("  ", LibraryStoredSearchKind.SavedSearch, query)
                    is null,
                "stored_search_refuses_an_empty_name");
            string? smartId = document.CreateStoredSearch(
                "Keepers",
                LibraryStoredSearchKind.SmartCollection,
                query);
            Check(smartId is not null, "stored_search_create");
            Check(document.StoredSearches.Count == 1, "stored_search_projected");
            Check(
                document.StoredSearches[0].Kind == LibraryStoredSearchKind.SmartCollection,
                "stored_search_keeps_its_kind");

            Check(document.RenameCollection(id!, "Roll 02"), "collections_rename");
            Check(document.Collections[0].Name == "Roll 02", "collections_rename_applied");
            Check(!document.RenameCollection(id!, "  "), "collections_refuse_an_empty_rename");
            Check(document.Save() == CatalogStoreError.None, "collections_save");
        }

        LibraryDocumentOpenResult reopened = LibraryDocument.Open(roots);
        if (reopened.Document is not { } reread)
        {
            Check(false, "collections_reopen_document");
            return;
        }
        using (reread)
        {
            Check(reread.Collections.Count == 1, "collections_survive_a_reopen");
            Check(reread.StoredSearches.Count == 1, "stored_search_survives_a_reopen");
            LibraryStoredQuery reloaded = reread.StoredSearches[0].Query;
            Check(
                reloaded.MinimumRating == 4 && reloaded.Picked && reloaded.Infrared &&
                reloaded.SearchText == "bukhansan",
                "stored_search_round_trips_the_condition");
            // 저장할 때의 필터로 되돌아가야 고른 것과 걸리는 것이 갈라지지 않습니다.
            LibraryQuickFilterState restored = reloaded.ToQuickFilters([]);
            Check(
                restored.MinimumRating == 4 && restored.Picked && restored.Infrared &&
                !restored.Rejected,
                "stored_search_restores_the_filters");
            Check(
                reread.DeleteStoredSearch(reread.StoredSearches[0].Id) &&
                reread.StoredSearches.Count == 0,
                "stored_search_delete");
            Check(reread.Collections[0].Name == "Roll 02", "collections_reread_the_name");
            Check(
                reread.DeleteCollection(reread.Collections[0].Id) &&
                reread.Collections.Count == 0,
                "collections_delete");
        }
        }
        finally
        {
            if (Directory.Exists(isolatedBase) &&
                StoragePathPolicy.IsLexicallyContained(parent, isolatedBase))
            {
                Directory.Delete(isolatedBase, true);
            }
        }
    }

    /// <summary>
    /// 롤 기록입니다. 롤 값은 프레임의 <b>비어 있는 칸만</b> 채워야 하고, 롤 토큰이 파일명에
    /// 실제로 나타나야 하며, 저장하고 다시 열었을 때 그대로 있어야 합니다.
    /// </summary>
    private static void VerifyLibraryRolls()
    {
        // 롤 값은 프레임에 없는 칸만 채웁니다 — 롤 중간에 렌즈를 바꾸는 일이 실제로 있습니다.
        RollRecord record = new(
            "R-2026-014",
            new FilmShotMetadata("Leica", "M6", "Summicron 35mm", "Portra 400", 400),
            "second half pushed one stop");
        FilmShotMetadata frameShot = new(CameraModel: "M3", LensModel: "Elmar 50mm");
        FilmShotMetadata? filled = record.Filling(frameShot);
        Check(
            filled is { CameraModel: "M3", LensModel: "Elmar 50mm", CameraMake: "Leica" },
            "roll_record_fills_only_empty_fields");
        Check(
            filled?.FilmStock == "Portra 400" && filled?.IsoSpeed == 400,
            "roll_record_supplies_the_missing_film");
        Check(
            record.Filling(filled) is null,
            "roll_record_reports_nothing_to_fill");
        Check(new RollRecord().Normalized().IsEmpty, "roll_record_empty");

        LibraryFrameSnapshot frame = Frame(
            new ManualBaseRgb(0.2, 0.2, 0.2),
            sourcePath: @"C:\scans\IMG_0007.tif") with
        {
            AppMetadata = new AppMetadataOverlay
            {
                FilmShot = new FilmShotMetadata(CameraModel: "M3"),
                Revision = 1,
            },
        };
        LibraryRollSnapshot roll = new(
            "roll-1",
            LibraryRollKind.Physical,
            "Roll 14",
            DateTimeOffset.UtcNow,
            FilmType.ColorNegative,
            [frame.Id],
            record);

        ExportNamingContext context = ExportNamingContexts.For(frame, roll, 3);
        ExportDestination destination = new(
            @"D:\Export",
            "{roll}-{rollcode}-{camera}-{film}-{sequence}",
            DevelopExportFormat.Tiff16);
        // 카메라는 프레임 값이 이기고, 필름은 프레임에 없으므로 롤 값이 옵니다.
        Check(
            destination.FileNameFor(frame.SourcePath, context)
                == "Roll 14-R-2026-014-M3-Portra 400-0003.tif",
            "roll_tokens_reach_the_filename");
        Check(
            ExportNamingTemplate.IsValid("{roll}{rollcode}{film}{camera}"),
            "roll_tokens_are_valid");

        string parent = Path.Combine(AppContext.BaseDirectory, "roll-tests");
        string isolatedBase = Path.Combine(parent, $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;
        string frameId = Guid.NewGuid().ToString("D");
        try
        {
            using (CatalogSession session = CatalogSession.Open(roots).Session!)
            {
                Check(session.ReadOrCreate().IsSuccess, "roll_catalog_create");
                Check(session.Write(new CatalogSnapshot(
                    null,
                    new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
                    {
                        [CatalogEntityTable.Frames] =
                        [new CatalogEntityRow(frameId, FrameRecord(frameId, "R_0001.tif", 0))],
                    })).IsSuccess, "roll_catalog_seed");
            }

            string? rollId;
            using (LibraryDocument document = LibraryDocument.Open(roots).Document!)
            {
                Check(
                    document.CreateRoll("  ", FilmType.ColorNegative, []) is null,
                    "roll_refuses_an_empty_name");
                rollId = document.CreateRoll(
                    "Roll 14",
                    FilmType.ColorNegative,
                    [frameId, "not-in-the-catalog"]);
                Check(rollId is not null, "roll_create");
                Check(
                    document.Rolls.Single().FrameIds.SequenceEqual([frameId]),
                    "roll_keeps_only_known_frames");
                Check(document.SetRollRecord(rollId!, record), "roll_set_record");
                Check(document.RollFor(frameId)?.Id == rollId, "roll_for_frame");
                Check(document.SetActiveRoll(rollId), "roll_set_active");
                Check(!document.SetActiveRoll("missing"), "roll_refuses_an_unknown_active");
                Check(document.Save() == CatalogStoreError.None, "roll_save");
            }

            using LibraryDocument reopened = LibraryDocument.Open(roots).Document!;
            Check(reopened.Rolls.Count == 1, "roll_survives_a_reopen");
            Check(
                reopened.Rolls[0].Record?.Code == "R-2026-014" &&
                reopened.Rolls[0].Record?.Shot?.CameraModel == "M6" &&
                reopened.Rolls[0].FilmType == FilmType.ColorNegative,
                "roll_record_round_trip");
            Check(reopened.ActiveRollId == rollId, "roll_active_round_trip");

            // 현재 롤 필터는 활성 롤의 사진만 남깁니다. 활성 롤이 없으면 아무 것도 걸러내지
            // 않습니다 — 켠 순간 격자가 비면 사용자는 사진이 사라졌다고 읽습니다.
            LibraryFrameListItem[] items =
            [
                new(reopened.Frames[0]),
                new(Frame(new ManualBaseRgb(0.2, 0.2, 0.2)) with { Id = "other" }),
            ];
            LibraryQuickFilterState filter = new()
            {
                CurrentRoll = true,
                CurrentRollFrameIds = reopened.Rolls[0].FrameIds,
            };
            Check(
                filter.Apply(items).Count == 1 &&
                filter.Apply(items)[0].Frame.Id == frameId,
                "current_roll_filter_keeps_the_active_roll");
            Check(
                !(filter with { CurrentRollFrameIds = [] }).IsActive,
                "current_roll_filter_is_inert_without_an_active_roll");
        }
        finally
        {
            if (Directory.Exists(isolatedBase) &&
                StoragePathPolicy.IsLexicallyContained(parent, isolatedBase))
            {
                Directory.Delete(isolatedBase, true);
            }
        }
    }

    /// <summary>
    /// 담아 둔 내보내기 설정입니다. 목적지와 파일명 패턴은 프리셋에 담기지도, 얹을 때 덮이지도
    /// 않아야 합니다 — 프리셋을 고르는 것이 내보낼 폴더를 바꾸는 뜻은 아닙니다.
    /// </summary>
    private static void VerifyExportRecipes()
    {
        ExportSettings current = new()
        {
            Format = DevelopExportFormat.Tiff16,
            Dpi = 300,
            LongEdge = 4096,
            FolderPath = @"D:\Export",
            NamingTemplate = "{name}-{sequence}",
            SequenceStart = 7,
        };

        ExportRecipeLibrary library = new ExportRecipeLibrary().Save("  Archive  ", current);
        Check(library.Recipes.Count == 1, "export_recipe_saved");
        Check(library.Recipes[0].Name == "Archive", "export_recipe_trims_the_name");
        Check(library.SelectedId == library.Recipes[0].Id, "export_recipe_selects_what_was_saved");
        Check(
            library.Recipes[0].Settings.FolderPath.Length == 0 &&
            library.Recipes[0].Settings.NamingTemplate == ExportNamingTemplate.DefaultPattern,
            "export_recipe_does_not_store_the_destination");

        ExportSettings elsewhere = current with
        {
            Format = DevelopExportFormat.Jpeg8,
            Dpi = 0,
            LongEdge = 0,
            FolderPath = @"E:\Somewhere",
            NamingTemplate = "{sequence}",
            SequenceStart = 42,
        };
        ExportSettings applied = library.Recipes[0].ApplyTo(elsewhere);
        Check(
            applied.Format == DevelopExportFormat.Tiff16 && applied.Dpi == 300 &&
            applied.LongEdge == 4096,
            "export_recipe_applies_the_encoding");
        Check(
            applied.FolderPath == @"E:\Somewhere" && applied.NamingTemplate == "{sequence}" &&
            applied.SequenceStart == 42,
            "export_recipe_keeps_the_current_destination");

        // 같은 이름으로 다시 담으면 덮어씁니다.
        ExportRecipeLibrary again = library.Save("Archive", elsewhere);
        Check(again.Recipes.Count == 1, "export_recipe_overwrites_the_same_name");
        Check(
            again.Recipes[0].Settings.Format == DevelopExportFormat.Jpeg8,
            "export_recipe_overwrite_takes_the_new_values");
        Check(
            new ExportRecipeLibrary().Save("   ", current).Recipes.Count == 0,
            "export_recipe_refuses_an_empty_name");
        // 목록에 없는 선택은 빈 선택입니다.
        Check(
            (again with { SelectedId = "missing" }).Normalize().SelectedId is null,
            "export_recipe_drops_a_dangling_selection");
        Check(again.Delete(again.Recipes[0].Id).Recipes.Count == 0, "export_recipe_delete");
    }

    /// <summary>
    /// 시뮬레이터로 스캔 경로를 끝까지 돌립니다. 이 기계에는 필름 스캐너도 플러그인도 없으므로,
    /// 검출부터 카탈로그 게시까지가 실제로 이어지는지 확인할 수 있는 유일한 길입니다.
    /// </summary>
}
