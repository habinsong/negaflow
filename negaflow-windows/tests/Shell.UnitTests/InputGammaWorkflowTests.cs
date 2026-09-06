using System.Text.Json.Nodes;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using static Negaflow.Shell.UnitTests.TestAssert;
using static Negaflow.Shell.UnitTests.TestFrameFactory;
using static Negaflow.Shell.UnitTests.DevelopTestResults;

namespace Negaflow.Shell.UnitTests;

internal static class InputGammaWorkflowTests
{
    public static void Run()
    {
        foreach (string text in new[] { "0.1", "0.2", "0.3", "1", "2.2", "4.0" })
        {
            Check(InputGammaValueInput.Accepts(text), "gamma_input_accepts_" + text);
            Check(InputGammaValueInput.TryValue(text, out _), "gamma_input_commits_" + text);
        }
        foreach (string text in new[] { "-1", "0.09", "4.01", "0.10", "2.20", "2.25", "2.19921875", "NaN", "Infinity", "2,2", "１.２", "1e0", "2.345" })
        {
            Check(!InputGammaValueInput.Accepts(text), "gamma_input_rejects_" + text);
            Check(!InputGammaValueInput.TryValue(text, out _), "gamma_commit_rejects_" + text);
        }
        var recorded = InputGammaInterpretation.Power(2.19921875);
        Check(InputGammaValueInput.Format(recorded.Value!.Value) == "2.2" && recorded.Value == 2.19921875,
            "gamma_display_uses_tenths_preserving_source_precision");
        Check(InputGammaValueInput.Round(2.25) == 2.3, "gamma_midpoint_rounds_like_macos");
        Check(InputGammaValueInput.Format(1) == "1.0", "gamma_display_keeps_one_decimal");
        Check(!InputGammaValueInput.TryValue("0.", out _), "gamma_incomplete_draft_not_committed");
        VerifyCodec();
        VerifySourceInspection();
        VerifyScalePreservation();
        if (OperatingSystem.IsWindows()) { VerifyWorkflow().GetAwaiter().GetResult(); }
        else { Console.Error.WriteLine("Windows file API unavailable; skipped input gamma catalog/undo workflow."); }
    }

    private static void VerifyScalePreservation()
    {
        foreach (double scale in new[] { 0.5, 0.75, 1.0, 1.25, 1.5 })
        {
            JsonObject record = FrameRecord("gamma-frame", "gamma.tiff", 0);
            record["rawScanPath"] = Path.Combine(Path.GetTempPath(), "gamma.tiff");
            record["params"]!["baseEstimationMode"] = "manual";
            record["params"]!["baseScale"] = scale;
            foreach (var gamma in new[] { InputGammaInterpretation.Power(0.3), InputGammaInterpretation.Power(4.0), InputGammaInterpretation.Automatic })
            {
                record["baseRGB"] = new JsonArray(0.7, 0.3, 0.2);
                var frame = LibraryFrameReader.Read(System.Text.Json.JsonSerializer.SerializeToElement(record)).Frame!;
                var result = LibraryFrameWriter.Apply(record, DevelopInputEditor.CreateEdit(frame, gamma));
                Check(result.Error == LibraryFrameError.None, "gamma_mode_edit_writes");
                var restored = LibraryFrameReader.Read(System.Text.Json.JsonSerializer.SerializeToElement(result.FrameRecord)).Frame!;
                Check(restored.Base.Scale == scale && restored.InputGamma == gamma, "gamma_mode_and_slider_preserve_scale");
                Check(restored.ManualBase is null && restored.Base.Mode == BaseEstimationMode.Auto, "gamma_remeasures_base");
                Check(!result.FrameRecord!.ContainsKey("baseRGB"), "gamma_edit_invalidates_measured_base");
                Check(frame.Base.Scale == scale, "gamma_edit_preserves_previous_snapshot");
                record = result.FrameRecord!;
            }
        }
    }

    private static void VerifySourceInspection()
    {
        InputGammaSourceInspection state = new();
        var first = state.Begin("source.tif", null)!.Value;
        Check(state.Begin("source.tif", null) is null, "gamma_virtual_copy_shares_pending_source_inspection");
        Negaflow.Interop.InputGammaSource.Info info = new(true,
            Negaflow.Interop.InputGammaSource.CurveKind.EmbeddedPower, 2.19921875);
        Check(state.Complete(first, info) && state.Info == info, "gamma_virtual_copy_accepts_original_inspection");
        state.Invalidate();
        Check(!state.Complete(first, info) && !state.Info.Supported, "gamma_unloaded_rejects_old_source_result");
        var reopened = state.Begin("source.tif", null)!.Value;
        Check(reopened.Revision != first.Revision, "gamma_reloaded_same_source_restarts_inspection");
        var different = state.Begin("second.tif", null)!.Value;
        Check(!state.Complete(reopened, info), "gamma_changed_source_rejects_late_inspection");
        Check(state.Complete(different, info), "gamma_current_source_accepts_inspection");
        LibrarySourceMetadata metadata = new(42, 10, 10, 3, 16, 1, 1);
        var changedMetadata = state.Begin("second.tif", metadata)!.Value;
        Check(!state.Complete(different, info), "gamma_metadata_change_rejects_old_inspection");
        Check(state.Complete(changedMetadata, info), "gamma_metadata_change_restarts_inspection");
        Check(info.AutomaticValue == 2.19921875, "gamma_automatic_readout_keeps_source_precision");
        foreach (var (curve, gamma, expected) in new (Negaflow.Interop.InputGammaSource.CurveKind, double, double?)[]
        {
            (Negaflow.Interop.InputGammaSource.CurveKind.EstimatedPower, 0.33, 0.33),
            (Negaflow.Interop.InputGammaSource.CurveKind.EmbeddedPower, 5.0, 5.0),
            (Negaflow.Interop.InputGammaSource.CurveKind.AssumedLinear, 0, 1.0),
            (Negaflow.Interop.InputGammaSource.CurveKind.AssumedSRGB, 0, 2.2),
            (Negaflow.Interop.InputGammaSource.CurveKind.EmbeddedProfile, 0, null),
            (Negaflow.Interop.InputGammaSource.CurveKind.Unknown, 0, null),
            (Negaflow.Interop.InputGammaSource.CurveKind.EmbeddedPower, double.NaN, null),
        })
        {
            Check(new Negaflow.Interop.InputGammaSource.Info(true, curve, gamma).AutomaticValue == expected,
                "gamma_automatic_readout_" + curve);
        }
    }

    private static void VerifyCodec()
    {
        JsonObject original = FrameRecord("gamma-frame", "gamma.tiff", 0);
        original["rawScanPath"] = Path.Combine(Path.GetTempPath(), "gamma.tiff");
        foreach (double value in new[] { 0.1, 0.22, 0.33, 1.2345, 2.19921875, 4.0 })
        {
            var before = LibraryFrameReader.Read(System.Text.Json.JsonSerializer.SerializeToElement(original)).Frame!;
            var result = LibraryFrameWriter.Apply(original, new LibraryFrameEdit(before.Tone, before.ManualBase, before.Base with { Scale = 0.75 })
                { InputGamma = InputGammaInterpretation.Power(value) });
            Check(result.Error == LibraryFrameError.None, "gamma_codec_write");
            var restored = LibraryFrameReader.Read(System.Text.Json.JsonSerializer.SerializeToElement(result.FrameRecord)).Frame;
            Check(restored?.InputGamma.Value == value && restored.Base.Scale == 0.75, "gamma_codec_roundtrip_exact");
            Check(!original["params"]!.AsObject().ContainsKey("inputGamma"), "gamma_codec_preserves_source_record");
        }
        foreach (JsonNode? invalid in new JsonNode?[] { null, JsonValue.Create("2.2"), JsonValue.Create(true), JsonValue.Create(0.09), JsonValue.Create(4.01) })
        {
            var record = original.DeepClone(); record["params"]!["inputGamma"] = invalid;
            Check(LibraryFrameReader.Read(System.Text.Json.JsonSerializer.SerializeToElement(record)).Frame is null, "gamma_codec_invalid_is_not_auto");
        }
    }

    private static async Task VerifyWorkflow()
    {
        string directory = Path.Combine(Path.GetTempPath(), "negaflow-gamma-workflow-" + Guid.NewGuid().ToString("N"));
        StorageRootSet roots = StorageRootResolver.ResolveForTests(directory).Roots!;
        try
        {
            JsonObject record = FrameRecord("gamma-frame", "gamma.tiff", 0);
            record["params"]!["baseEstimationMode"] = "manual";
            record["params"]!["baseScale"] = 0.75;
            using (CatalogSession seed = CatalogSession.Open(roots).Session!)
            {
                var written = seed.Write(new CatalogSnapshot(null,
                    new Dictionary<CatalogEntityTable, IReadOnlyList<CatalogEntityRow>>
                    { [CatalogEntityTable.Frames] = [new("gamma-frame", record)] }));
                Check(written.Error == CatalogStoreError.None, "gamma_seed_write_" + written.Error);
            }
            using LibraryHostService host = new(new FakeDispatcher(accepts: true), new FakeExporter(_ => OkResult()));
            var opened = host.Open(roots);
            Check(opened == LibraryHostState.Open && host.Frames.Count == 1,
                $"gamma_host_open_{opened}_{host.StoreError}_{host.SessionError}_{host.DefectSidecarError}_frames_{host.Frames.Count}");
            if (host.Frames.Count != 1) { return; }
            LibraryFrameSnapshot current() => host.Frames.Single();
            JsonObject before = host.FrameRecord("gamma-frame")!;
            DevelopInputEditor rejected = new(host, (_, _) => Task.FromResult(false));
            Check(await rejected.SetAsync(current(), InputGammaInterpretation.Power(1.8), current) == LibraryFrameError.InvalidBaseRecipe,
                "gamma_unsupported_source_rejected");
            Check(JsonNode.DeepEquals(before, host.FrameRecord("gamma-frame")), "gamma_failure_preserves_entire_recipe");

            DevelopInputEditor accepted = new(host, (_, _) => Task.FromResult(true));
            Check(await accepted.SetAsync(current(), InputGammaInterpretation.Power(1.2345), current) == LibraryFrameError.None,
                "gamma_valid_edit_applied");
            Check(current().InputGamma.Value == 1.2345 && current().Base.Scale == 0.75 && current().Base.Mode == BaseEstimationMode.Auto,
                "gamma_preserves_scale_and_remeasures_base_as_one_edit");
            host.Undo();
            Check(current().InputGamma.IsAutomatic && current().Base.Scale == 0.75 && current().Base.Mode == BaseEstimationMode.Manual,
                "gamma_single_undo_restores_base_and_input");
            host.Redo();
            Check(current().InputGamma.Value == 1.2345, "gamma_redo_preserves_precision");
            Check(current().Base.Scale == 0.75, "gamma_redo_preserves_scale");

            TaskCompletionSource<bool> validation = new(TaskCreationOptions.RunContinuationsAsynchronously);
            DevelopInputEditor delayed = new(host, (_, _) => validation.Task);
            Task<LibraryFrameError> pending = delayed.SetAsync(current(), InputGammaInterpretation.Power(2.4), current);
            delayed.Cancel();
            validation.SetResult(true);
            Check(await pending == LibraryFrameError.MissingId && current().InputGamma.Value == 1.2345,
                "gamma_cancelled_validation_cannot_publish");
            Check(await accepted.SetAsync(current(), InputGammaInterpretation.Automatic, current) == LibraryFrameError.None,
                "gamma_automatic_mode_restored");
            Check(host.FrameRecord("gamma-frame")!["params"]!.AsObject().ContainsKey("inputGamma") == false,
                "gamma_automatic_uses_legacy_default_encoding");
            Check(current().Base.Scale == 0.75, "gamma_automatic_preserves_scale");

            var beforePaste = current();
            var copied = beforePaste with { InputGamma = InputGammaInterpretation.Power(1.8),
                Base = beforePaste.Base with { Scale = 1.25 } };
            Check(host.EditUndoable(beforePaste.Id, LibraryHostService.UndoActions.DevelopAdjustment,
                record => DevelopSettingsTransfer.Paste(record, copied, current(), DevelopSettingsPasteScope.All)) == LibraryFrameError.None,
                "gamma_paste_uses_existing_record_undo");
            Check(current().InputGamma.Value == 1.8 && current().Base.Scale == 1.25,
                "gamma_paste_applies_both_fields");
            host.Undo();
            Check(current().InputGamma == beforePaste.InputGamma && current().Base == beforePaste.Base,
                "gamma_paste_undo_restores_both_fields");
            host.Redo();
            Check(current().InputGamma.Value == 1.8 && current().Base.Scale == 1.25,
                "gamma_paste_redo_restores_both_fields");
        }
        finally { if (Directory.Exists(directory)) { Directory.Delete(directory, recursive: true); } }
    }
}
