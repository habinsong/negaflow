using System.Text.Json.Nodes;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Library;
using static Negaflow.Shell.UnitTests.TestAssert;
using static Negaflow.Shell.UnitTests.DevelopTestResults;
using static Negaflow.Shell.UnitTests.TestFrameFactory;

namespace Negaflow.Shell.UnitTests;

internal static class DevelopPresetTransferTests
{
    public static void Run()
    {
        string root = Path.Combine(Path.GetTempPath(), "negaflow-preset-transfer-" + Guid.NewGuid().ToString("N"));
        var roots = StorageRootResolver.ResolveForTests(root).Roots!;
        try
        {
            using (var seed = CatalogSession.Open(roots).Session!)
            {
                seed.Write(new CatalogSnapshot(null, new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
                {
                    [CatalogEntityTable.Frames] = [
                        new("source", FrameRecord("source", "source.tif", 0.65)),
                        new("first", FrameRecord("first", "first.tif", -0.3)),
                        new("second", FrameRecord("second", "second.tif", 0.2)),
                    ],
                }));
            }
            using var host = new LibraryHostService(new FakeDispatcher(true), new FakeExporter(_ => OkResult()));
            host.Open(roots);
            var panel = new DevelopPanelState(host, new ToneLimits(5, 1, 2, 0, 1), new NegativeLimits(0.001f, 1));
            panel.Select("source");
            Check(panel.CopyDevelopSettings(), "bulk_copy_captures_source");
            host.SetSelection(["first", "second", "second"], "first");
            panel.Select("first");
            var beforeFirst = host.FrameRecord("first")!;
            var beforeSecond = host.FrameRecord("second")!;
            int edits = 0;
            host.FrameEdited += (_, _) => ++edits;
            Check(panel.PasteDevelopSettings() == LibraryFrameError.None, "bulk_paste_succeeds");
            Check(host.Frames.Where(frame => frame.Id != "source").All(frame => frame.Tone.Exposure == 0.65),
                  "bulk_paste_replaces_every_selected_frame");
            Check(host.SelectedFrameIds.SequenceEqual(new[] { "first", "second" }) && edits == 1,
                  "bulk_paste_preserves_selection_and_publishes_once");
            Check(host.Undo() is not null && JsonNode.DeepEquals(host.FrameRecord("first"), beforeFirst) &&
                JsonNode.DeepEquals(host.FrameRecord("second"), beforeSecond), "bulk_paste_undo_restores_all_targets");
            Check(host.Redo() is not null && host.Frames.All(frame => frame.Tone.Exposure == 0.65),
                  "bulk_paste_redo_restores_all_targets");
            panel.RefreshSelectedFrame();
            var once = host.FrameRecord("first");
            edits = 0;
            panel.PasteDevelopSettings();
            Check(edits == 0 && JsonNode.DeepEquals(once, host.FrameRecord("first")), "repeated_paste_is_a_noop");

            panel.OpenUserPresets(Path.Combine(root, "presets.json"));
            panel.Select("source");
            var preset = panel.SaveUserPreset("Saved");
            Check(preset is not null, "preset_persists_before_reporting_success");
            host.Undo(); // 붙여넣기 전의 서로 다른 값으로 돌아간다.
            panel.Select("first");
            edits = 0;
            Check(panel.ApplyUserPreset(preset!.Id) == LibraryFrameError.None &&
                host.Frames.All(frame => frame.Tone.Exposure == 0.65) && edits == 1,
                "user_preset_replaces_entire_selection_once");
            Check(host.Undo() is not null && JsonNode.DeepEquals(host.FrameRecord("first"), beforeFirst) &&
                JsonNode.DeepEquals(host.FrameRecord("second"), beforeSecond), "bulk_user_preset_has_one_undo_step");

            edits = 0;
            var priorUndo = host.UndoActionName;
            var error = host.EditFrameRecordsUndoable(["first", "second"], "Preset",
                (id, record) => id == "second" ? new LibraryFrameWriteResult(null, LibraryFrameError.InvalidDevelopRoute)
                    : LibraryFrameWriter.Apply(record, new LibraryFrameEdit(new ToneAdjustment(0.4, 0, 0, 0, 0, 0), null)));
            Check(error != LibraryFrameError.None && edits == 0 && host.UndoActionName == priorUndo &&
                JsonNode.DeepEquals(host.FrameRecord("first"), beforeFirst) && JsonNode.DeepEquals(host.FrameRecord("second"), beforeSecond),
                "invalid_bulk_transfer_leaves_all_frames_and_history_untouched");
            string unwritablePresetFile = Path.Combine(root, "directory-as-preset-file");
            Directory.CreateDirectory(unwritablePresetFile);
            panel.OpenUserPresets(unwritablePresetFile);
            panel.Select("source");
            Check(panel.SaveUserPreset("Cannot persist") is null && panel.UserPresets.Count == 0,
                "failed_preset_write_does_not_add_a_fake_saved_preset");
        }
        finally { if (Directory.Exists(root)) { Directory.Delete(root, true); } }
    }
}
