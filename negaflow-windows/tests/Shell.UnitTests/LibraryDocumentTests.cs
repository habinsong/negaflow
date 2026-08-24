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

internal static class LibraryDocumentTests
{
    public static void Run()
    {
        VerifyLibraryDocument();
    }

    private static void VerifyLibraryDocument()
    {
        string testParent = Path.Combine(AppContext.BaseDirectory, "library-document-tests");
        string isolatedBase = Path.Combine(
            testParent,
            $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;

        try
        {
            LibraryDocumentOpenResult opened = LibraryDocument.Open(roots);
            Check(opened.IsSuccess, "library_document_open");
            using (LibraryDocument document = opened.Document!)
            {
                Check(document.Frames.Count == 0, "library_document_starts_empty");
                Check(document.Issues.Count == 0, "library_document_no_issues_when_empty");

                // 두 번째 작성자는 세션 lock 에서 막힙니다.
                LibraryDocumentOpenResult second = LibraryDocument.Open(roots);
                Check(!second.IsSuccess, "library_document_second_open_rejected");
                Check(
                    second.Error == LibraryDocumentError.SessionBusy,
                    "library_document_second_open_busy");
            }

            SeedFrames(roots);
            VerifyLibraryDocumentRoundTrip(roots);
            VerifyDevelopSettingsPastePersists(roots);
            VerifyLibraryDocumentPreservesNonFrameRows(roots);
            LibraryStructureTests.VerifyLibraryFrameRemoval(isolatedBase);
            LibraryStructureTests.VerifyLibraryStacks(isolatedBase);
            LibraryStructureTests.VerifyVirtualCopies(isolatedBase);
            LibraryCullingTests.VerifyLibraryUndo(isolatedBase);
            LibraryCullingTests.VerifyLibraryUndoSaveFailure(isolatedBase);
            LibraryStructureTests.VerifyLibraryDocumentDefectProjection(isolatedBase);
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

    /// <summary>
    /// 가상 사본은 같은 원본을 가리키는 두 번째 줄입니다. 원본 파일은 하나 그대로이고, 이
    /// 빌드가 모르는 field 까지 함께 넘어가야 두 사진의 현상 결과가 갈리지 않습니다.
    /// </summary>
    private static void SeedFrames(StorageRootSet roots)
    {
        using CatalogSession session = CatalogSession.Open(roots).Session!;
        List<CatalogEntityRow> rows =
        [
            new("frame-1", FrameRecord("frame-1", "IMG_0001.tif", 0.0)),
            new("frame-2", FrameRecord("frame-2", "IMG_0002.tif", 0.5)),
            // 투영이 실패할 record. 목록에서 빠지되 없어지지는 않아야 합니다.
            new("frame-3", new JsonObject
            {
                ["id"] = "frame-3",
                ["sourceKind"] = "scanner",
                ["filmType"] = "colorNegative",
                ["params"] = new JsonObject { ["filmType"] = "colorNegative" },
            }),
        ];
        Check(
            session.Write(new CatalogSnapshot(
                null,
                new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
                {
                    [CatalogEntityTable.Frames] = rows,
                })).IsSuccess,
            "library_document_seed_write");
    }

    private static void VerifyLibraryDocumentRoundTrip(StorageRootSet roots)
    {
        using (LibraryDocument document = LibraryDocument.Open(roots).Document!)
        {
            Check(document.RecordCount == 3, "library_document_keeps_every_record");
            Check(document.Frames.Count == 2, "library_document_projects_readable_frames");
            Check(
                string.Join(',', document.Frames.Select(frame => frame.Id)) ==
                    "frame-1,frame-2",
                "library_document_preserves_order");

            // 읽지 못한 frame 을 조용히 버리면 사용자에게는 사진이 사라진 것으로 보입니다.
            Check(document.Issues.Count == 1, "library_document_reports_unreadable_frame");
            Check(document.Issues[0].Id == "frame-3", "library_document_issue_id");
            Check(
                document.Issues[0].Error == LibraryFrameError.MissingSourcePath,
                "library_document_issue_error");

            Check(
                document.Edit(
                    "frame-1",
                    new LibraryFrameEdit(
                        new ToneAdjustment(1.75, 0, 0, 0, 0, 0),
                        new ManualBaseRgb(0.31, 0.32, 0.33))) == LibraryFrameError.None,
                "library_document_edit");
            Check(
                document.Frames[0].Tone.Exposure == 1.75,
                "library_document_edit_visible_immediately");
            Check(
                document.Edit("missing", new LibraryFrameEdit(ToneAdjustment.Neutral, null)) ==
                    LibraryFrameError.MissingId,
                "library_document_edit_unknown_id");
            Check(document.Save() == CatalogStoreError.None, "library_document_save");
        }

        // 앱을 껐다 켠 것과 같습니다.
        using LibraryDocument reopened = LibraryDocument.Open(roots).Document!;
        Check(reopened.Frames[0].Tone.Exposure == 1.75, "library_document_edit_persisted");
        Check(
            reopened.Frames[0].ManualBase == new ManualBaseRgb(0.31, 0.32, 0.33),
            "library_document_base_persisted");
        Check(reopened.Frames[1].Tone.Exposure == 0.5, "library_document_other_frame_untouched");
        Check(
            reopened.RecordCount == 3,
            "library_document_save_did_not_drop_unreadable_record");
        Check(
            reopened.Issues.Count == 1,
            "library_document_unreadable_record_survives_save");
    }

    /// <summary>
    /// 붙여넣기가 catalog 를 지나 디스크까지 살아남는지 봅니다. 레코드 수준 규칙은 catalog
    /// 테스트가 보고, 여기서는 저장·재시작 경계만 봅니다.
    /// </summary>
    private static void VerifyDevelopSettingsPastePersists(StorageRootSet roots)
    {
        using (LibraryDocument document = LibraryDocument.Open(roots).Document!)
        {
            LibraryFrameSnapshot source = document.Frames[0];
            LibraryFrameSnapshot destination = document.Frames[1];
            Check(source.Tone.Exposure != destination.Tone.Exposure,
                "paste_persist_frames_differ_before");
            Check(document.EditFrameRecord(
                    destination.Id,
                    record => DevelopSettingsTransfer.Paste(
                        record, source, destination, DevelopSettingsPasteScope.All)) ==
                LibraryFrameError.None,
                "paste_persist_edit");
            Check(document.Frames[1].Tone.Exposure == source.Tone.Exposure,
                "paste_persist_visible_immediately");
            Check(document.Frames[1].SourcePath == destination.SourcePath,
                "paste_persist_keeps_destination_photo");
            Check(document.Save() == CatalogStoreError.None, "paste_persist_save");
        }

        using LibraryDocument restarted = LibraryDocument.Open(roots).Document!;
        Check(restarted.Frames[1].Tone.Exposure == restarted.Frames[0].Tone.Exposure,
            "paste_persist_survives_restart");
    }

    private static void VerifyLibraryDocumentPreservesNonFrameRows(StorageRootSet roots)
    {
        Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>> tables = [];
        foreach (CatalogEntityTable table in CatalogEntityTables.All)
        {
            tables[table] = table == CatalogEntityTable.Frames
                ? [new CatalogEntityRow("frame-1", FrameRecord("frame-1", "IMG_0001.tif", 0.0))]
                : [new CatalogEntityRow(
                    $"{CatalogEntityTables.SqlName(table)}-1",
                    new JsonObject { ["marker"] = CatalogEntityTables.SqlName(table) })];
        }

        using (CatalogSession seed = CatalogSession.Open(roots).Session!)
        {
            Check(seed.Write(new CatalogSnapshot("active-roll", tables)).IsSuccess,
                "library_document_non_frame_seed");
        }

        using (LibraryDocument document = LibraryDocument.Open(roots).Document!)
        {
            Check(document.Edit(
                    "frame-1",
                    new LibraryFrameEdit(
                        new ToneAdjustment(0.75, 0, 0, 0, 0, 0),
                        new ManualBaseRgb(0.21, 0.22, 0.23))) == LibraryFrameError.None &&
                  document.Save() == CatalogStoreError.None,
                "library_document_non_frame_preserving_save");
        }

        using CatalogSession reader = CatalogSession.Open(roots).Session!;
        CatalogReadResult read = reader.ReadOrCreate();
        Check(
            read.Snapshot is { } snapshot && snapshot.ActiveRollId == "active-roll" &&
            CatalogEntityTables.All
                .Where(table => table != CatalogEntityTable.Frames)
                .All(table => snapshot.Rows(table).Count == 1 &&
                    snapshot.Rows(table)[0].Payload["marker"]?.GetValue<string>() ==
                    CatalogEntityTables.SqlName(table)),
            "library_document_save_preserves_every_non_frame_table");
    }

    /// <summary>
    /// 현상 편집은 메모리에서 먼저 일어납니다. 창을 닫을 때 쓰지 않으면 조용히 사라지므로,
    /// 이 계약은 시험으로 붙들어 둡니다 — 실제로 그렇게 잃고 있었습니다.
    /// </summary>
}
