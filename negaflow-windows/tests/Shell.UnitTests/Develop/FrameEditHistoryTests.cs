using System.Text.Json.Nodes;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Library;
using static Negaflow.Shell.UnitTests.DevelopTestResults;
using static Negaflow.Shell.UnitTests.TestAssert;
using static Negaflow.Shell.UnitTests.TestFrameFactory;

namespace Negaflow.Shell.UnitTests;

/// <summary>macOS <c>AppModel+FrameEditHistory</c>. 신쇄 <see cref="FrameEditHistory"/>.</summary>
internal static class FrameEditHistoryTests
{
    public static void Run()
    {
        Check(FrameEditHistory.CoalesceSeconds == 0.7, "frame_edit_coalesce_0_7");

        FrameEditHistory history = new();
        DateTime t0 = new(2026, 8, 19, 12, 0, 0, DateTimeKind.Utc);
        Check(history.ConsumeCapture("frame-1", t0), "first_edit_captures");
        Check(!history.ConsumeCapture("frame-1", t0.AddSeconds(0.2)), "drag_does_not_recapture");
        Check(!history.ConsumeCapture("frame-1", t0.AddSeconds(0.6)), "extended_window_still_same_gesture");
        Check(history.ConsumeCapture("frame-1", t0.AddSeconds(1.4)), "idle_starts_new_gesture");
        Check(history.ConsumeCapture("frame-2", t0.AddSeconds(1.41)), "other_frame_is_new_gesture");
        history.Clear("frame-2");
        Check(history.ConsumeCapture("frame-2", t0.AddSeconds(1.42)), "clear_allows_new_capture");

        string isolatedBase = Path.Combine(
            Path.Combine(AppContext.BaseDirectory, "frame-edit-history-tests"),
            $"{Environment.ProcessId}-{Guid.NewGuid():N}");
        StorageRootSet roots = StorageRootResolver.ResolveForTests(isolatedBase).Roots!;
        ToneLimits limits = new(5.0f, 1.0f, 2.0f, 0.0, 1.0);
        NegativeLimits negativeLimits = new(0.001f, 1.0f);
        try
        {
            using (CatalogSession seed = CatalogSession.Open(roots).Session!)
            {
                seed.Write(new CatalogSnapshot(
                    null,
                    new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
                    {
                        [CatalogEntityTable.Frames] =
                        [
                            new("frame-1", FrameRecord("frame-1", "IMG_0001.tif", 0.0)),
                        ],
                    }));
            }

            FakeDispatcher dispatcher = new(accepts: true);
            FakeExporter exporter = new(_ => OkResult());
            using LibraryHostService host = new(dispatcher, exporter);
            host.Open(roots);
            DevelopPanelState panel = new(host, limits, negativeLimits);
            Check(panel.Select("frame-1"), "history_select");
            Check(panel.Tone.SetExposure(1.0) == LibraryFrameError.None, "history_set_1");
            Check(panel.Tone.SetExposure(2.0) == LibraryFrameError.None, "history_set_2");
            Check(host.CanUndo, "history_slider_is_undoable");
            Check(
                host.UndoActionName == LibraryHostService.UndoActions.DevelopAdjustment,
                "history_undo_name");
            Check(host.Undo() == LibraryHostService.UndoActions.DevelopAdjustment, "history_undo");
            Check(panel.Select("frame-1"), "history_reselect");
            Check(panel.Tone.Exposure == 0, "history_undo_skips_mid_drag");
        }
        finally
        {
            if (Directory.Exists(isolatedBase))
            {
                Directory.Delete(isolatedBase, recursive: true);
            }
        }
    }
}
