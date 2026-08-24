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

internal static class LibraryCullingTests
{
    public static void Run()
    {
        VerifyLibraryCulling();
    }

    internal static void VerifyLibraryUndo(string parent)
    {
        StorageRootSet roots = StorageRootResolver.ResolveForTests(
            Path.Combine(parent, "undo")).Roots!;

        using (CatalogSession seed = CatalogSession.Open(roots).Session!)
        {
            Check(
                seed.Write(new CatalogSnapshot(
                    null,
                    new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
                    {
                        [CatalogEntityTable.Frames] =
                        [
                            new("frame-1", FrameRecord("frame-1", "IMG_0001.tif", 0.0, 1)),
                            new("frame-2", FrameRecord("frame-2", "IMG_0002.tif", 0.5, 2)),
                            new("frame-3", FrameRecord("frame-3", "IMG_0003.tif", 1.0, 3)),
                        ],
                        [CatalogEntityTable.ManualCollections] =
                        [
                            new("collection-1", new JsonObject
                            {
                                ["id"] = "collection-1",
                                ["name"] = "Keepers",
                                ["frameIDs"] = new JsonArray("frame-1", "frame-2"),
                            }),
                        ],
                    })).IsSuccess,
                "library_undo_seed");
        }

        using LibraryDocument document = LibraryDocument.Open(roots).Document!;
        Check(!document.CanUndo && !document.CanRedo, "library_undo_starts_empty");

        document.CaptureUndo("remove");
        Check(document.RemoveFrames(["frame-2"]).Count == 1, "library_undo_removal");
        Check(document.Frames.Count == 2, "library_undo_removal_applied");
        Check(document.CanUndo && document.UndoActionName == "remove", "library_undo_available");

        Check(document.Undo() == "remove", "library_undo_returns_the_action");
        Check(document.Frames.Count == 3, "library_undo_restores_the_frame");
        // 자리까지 돌아와야 합니다 — 끝에 다시 붙이면 정렬이 "입력 순서"인 사용자에게는
        // 사진이 옮겨 다닌 것으로 보입니다.
        Check(
            string.Join(',', document.Frames.Select(frame => frame.Id)) ==
                "frame-1,frame-2,frame-3",
            "library_undo_restores_the_position");
        // 소속도 돌아와야 합니다.
        Check(
            document.Collections[0].FrameIds.Count == 2,
            "library_undo_restores_collection_membership");
        Check(document.CanRedo, "library_undo_enables_redo");

        Check(document.Redo() == "remove", "library_redo_returns_the_action");
        Check(document.Frames.Count == 2, "library_redo_applies_again");
        Check(document.Undo() == "remove", "library_undo_after_redo");
        Check(document.Frames.Count == 3, "library_undo_after_redo_restores");

        // 되돌린 뒤 다른 길로 가면 옛 앞길은 사라집니다.
        document.CaptureUndo("stack");
        Check(document.CreateStack(["frame-1", "frame-3"]) is not null, "library_undo_new_branch");
        Check(!document.CanRedo, "library_undo_new_edit_clears_redo");
        Check(document.Undo() == "stack", "library_undo_the_stack");
        Check(document.Stacks.Count == 0, "library_undo_removes_the_stack");

        // 담아 둔 상태는 깊은 복사여야 합니다. 얕으면 뒤 편집이 담아 둔 것까지 바꿉니다.
        document.CaptureUndo("tone");
        Check(
            document.Edit(
                "frame-1",
                new LibraryFrameEdit(new ToneAdjustment(2.5, 0, 0, 0, 0, 0), null)) ==
                LibraryFrameError.None,
            "library_undo_tone_edit");
        Check(document.Frames[0].Tone.Exposure == 2.5, "library_undo_tone_applied");
        Check(document.Undo() == "tone", "library_undo_tone");
        Check(document.Frames[0].Tone.Exposure == 0.0, "library_undo_tone_restored");

        // 더미는 깊이가 제한됩니다.
        for (int index = 0; index < LibraryUndoStack.MaximumDepth + 5; ++index)
        {
            document.CaptureUndo("depth");
            _ = document.CreateVirtualCopy("frame-1");
        }
        int undone = 0;
        while (document.Undo() is not null)
        {
            ++undone;
        }
        Check(
            undone == LibraryUndoStack.MaximumDepth,
            "library_undo_depth_is_capped");
    }

    internal static void VerifyLibraryUndoSaveFailure(string parent)
    {
        StorageRootSet roots = StorageRootResolver.ResolveForTests(
            Path.Combine(parent, "undo-save-failure")).Roots!;
        JsonObject frame = FrameRecord("frame-1", "IMG_0001.tif", 0.0, 1);

        using CatalogSession session = CatalogSession.Open(roots).Session!;
        Check(
            session.Write(new CatalogSnapshot(
                null,
                new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
                {
                    [CatalogEntityTable.Frames] = [new("frame-1", frame)],
                })).IsSuccess,
            "library_undo_failure_seed");

        CatalogSnapshot snapshot = session.Read().Snapshot!;
        List<CatalogEntityRow> frameRows = [.. snapshot.Rows(CatalogEntityTable.Frames)];
        var retainedRows = CatalogEntityTables.All
            .Where(table => table != CatalogEntityTable.Frames)
            .ToDictionary(
                table => table,
                table => (IReadOnlyList<CatalogEntityRow>)[.. snapshot.Rows(table)]);
        var state = new LibraryDocumentState(
            session,
            [.. frameRows.Select(row => row.Id)],
            [.. frameRows.Select(row => (JsonObject)row.Payload.DeepClone())],
            retainedRows,
            snapshot.ActiveRollId);
        var persistence = new LibraryCatalogPersistence(state);
        CatalogStoreError injectedError = CatalogStoreError.None;
        var undo = new LibraryUndoCoordinator(
            state,
            new LibraryDefectRecipeStore(state),
            () => injectedError == CatalogStoreError.None
                ? persistence.Save()
                : injectedError);
        var editor = new LibraryFrameEditor(state);

        undo.CaptureUndo("tone");
        Check(
            editor.Edit(
                "frame-1",
                new LibraryFrameEdit(new ToneAdjustment(2.5, 0, 0, 0, 0, 0), null)) ==
                LibraryFrameError.None &&
            persistence.Save() == CatalogStoreError.None,
            "library_undo_failure_current_state_is_durable");

        injectedError = CatalogStoreError.IoFailure;
        LibraryHistoryResult undoFailure = undo.Undo();
        Check(
            undoFailure.ActionName is null &&
            undoFailure.CatalogError == CatalogStoreError.IoFailure &&
            state.Frames.Single().Tone.Exposure == 2.5 &&
            undo.CanUndo && !undo.CanRedo &&
            undo.UndoActionName == "tone" &&
            !state.IsDirty,
            "library_undo_save_failure_preserves_memory_stack_and_dirty_state");

        injectedError = CatalogStoreError.None;
        Check(
            undo.Undo().ActionName == "tone" &&
            state.Frames.Single().Tone.Exposure == 0.0 &&
            !undo.CanUndo && undo.CanRedo,
            "library_undo_success_moves_stack_after_save");

        injectedError = CatalogStoreError.IoFailure;
        LibraryHistoryResult redoFailure = undo.Redo();
        Check(
            redoFailure.ActionName is null &&
            redoFailure.CatalogError == CatalogStoreError.IoFailure &&
            state.Frames.Single().Tone.Exposure == 0.0 &&
            !undo.CanUndo && undo.CanRedo &&
            undo.RedoActionName == "tone" &&
            !state.IsDirty,
            "library_redo_save_failure_preserves_memory_stack_and_dirty_state");

        injectedError = CatalogStoreError.RollbackFailed;
        LibraryHistoryResult rollbackFailure = undo.Redo();
        Check(
            rollbackFailure.ActionName is null &&
            rollbackFailure.RequiresRecovery &&
            rollbackFailure.CatalogError == CatalogStoreError.RollbackFailed &&
            state.Frames.Single().Tone.Exposure == 2.5 &&
            !undo.CanUndo && undo.CanRedo &&
            !state.IsDirty,
            "library_redo_rollback_failure_reports_recovery_without_false_memory_restore");

        session.Dispose();
        using LibraryDocument reopened = LibraryDocument.Open(roots).Document!;
        Check(
            reopened.Frames.Single().Tone.Exposure == 0.0,
            "library_undo_redo_save_failure_restart_keeps_last_durable_state");
    }


    /// <summary>
    /// 비교·살펴보기에 올라가는 사진은 **격자에 보이는 차례**를 따라야 합니다 — 고른 차례가
    /// 아닙니다. 정렬을 바꾼 뒤 비교를 열었을 때 좌우가 화면과 어긋나면 어느 쪽이 어느 쪽인지
    /// 알 수 없습니다.
    /// </summary>
    private static void VerifyLibraryCulling()
    {
        string[] ordered = ["a", "b", "c", "d"];

        // 고른 차례가 아니라 격자 차례로 늘어놓습니다.
        Check(
            string.Join(',', LibraryCullingProjection.SelectedFrameIds(ordered, ["d", "b"])) ==
                "b,d",
            "culling_selection_follows_the_grid_order");
        // 격자에 없는 id 는 빠집니다.
        Check(
            LibraryCullingProjection.SelectedFrameIds(ordered, ["z"]).Count == 0,
            "culling_selection_drops_unknown_ids");

        // 두 장이 안 되면 비교가 아닙니다.
        Check(
            LibraryCullingProjection.CompareFrameIds(ordered, ["b"], "b").Count == 0,
            "culling_compare_needs_two");

        // 후보는 활성 사진, 기준은 그 앞의 첫 사진입니다.
        Check(
            string.Join(',', LibraryCullingProjection.CompareFrameIds(
                ordered, ["a", "b", "c"], "c")) == "a,c",
            "culling_compare_puts_the_active_photo_second");
        // 활성이 고른 것 밖이면 두 번째를 후보로 씁니다.
        Check(
            string.Join(',', LibraryCullingProjection.CompareFrameIds(
                ordered, ["a", "b", "c"], "d")) == "a,b",
            "culling_compare_falls_back_to_the_second");
        // 활성이 첫 사진이면 기준은 그 다음 사진이어야 합니다 — 자기 자신과 견줄 수 없습니다.
        IReadOnlyList<string> firstActive = LibraryCullingProjection.CompareFrameIds(
            ordered, ["a", "b"], "a");
        Check(
            firstActive.Count == 2 && firstActive[0] != firstActive[1] &&
                firstActive[1] == "a",
            "culling_compare_never_pairs_a_photo_with_itself");
    }


    /// <summary>
    /// 인화 판의 기하입니다. 여기 수가 macOS 와 다르면 같은 설정에서 다른 크기의 인화물이
    /// 나옵니다 — 사용자가 눈으로 알아채기 가장 어려운 종류의 어긋남입니다.
    /// </summary>
}
