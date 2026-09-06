using System.Xml.Linq;
using System.Text.Json.Nodes;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Print;
using static Negaflow.Shell.UnitTests.TestAssert;
using static Negaflow.Shell.UnitTests.TestFrameFactory;

namespace Negaflow.Shell.UnitTests;

internal static class ExportArtifactSafetyTests
{
    internal static void Run()
    {
        string directory = Path.Combine(Path.GetTempPath(), "negaflow-artifact-test-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        try
        {
            string source = Path.Combine(directory, "source.tif");
            File.WriteAllBytes(source, [1, 2, 3, 4]);
            var frame = Frame(null, sourcePath: source) with { InputGamma = InputGammaInterpretation.Power(1.8), Base = BaseRecipe.Auto with { Scale = 1.25 } };
            var settings = new ExportSettings { FolderPath = directory, NamingTemplate = "{name}", WriteSidecar = true, WriteOriginalRaw = true, WriteMainFlatMaster = true };
            string destination = settings.Destination.PathFor(source);
            File.WriteAllText(ExportArtifactPairing.XmpPath(destination), "external metadata");
            string safe = ExportBatchCoordinator.UniquePath(destination, settings, source);
            Check(safe != destination, "workflow_unique_name_reserves_existing_xmp");
            File.WriteAllText(ExportFlatMaster.PathFor(safe), "existing master");
            Check(ExportBatchCoordinator.UniquePath(destination, settings, source) != safe,
                "workflow_unique_name_reserves_master");
            var plans = ExportBatchCoordinator.Plan([frame], settings);
            Check(plans[0].Snapshot?.InputGamma.Value == 1.8 && plans[0].Snapshot?.Base.Scale == 1.25,
                "workflow_batch_keeps_planned_recipe_snapshot");
            var parameters = new JsonObject { ["inputGamma"] = 1.8, ["baseScale"] = 1.25 };
            string output = Path.Combine(directory, "safe.jpg");
            var captured = ExportArtifactSnapshot.Capture(frame, output, settings, settings.ToEncodingOptions(), parameters, "test", "test");
            parameters["inputGamma"] = 2.4; parameters["baseScale"] = 0.75;
            Check(ExportArtifactWriter.Write(captured) is null, "workflow_writes_captured_sidecars_and_original_copy");
            Check(captured.Content.Parameters!["inputGamma"]!.GetValue<double>() == 1.8 &&
                captured.Content.Parameters["baseScale"]!.GetValue<double>() == 1.25, "workflow_export_artifacts_keep_starting_gamma_and_scale");
            var sidecar = JsonNode.Parse(File.ReadAllText(ExportArtifactPairing.SidecarPath(output)))!;
            Check(sidecar["parameters"]!["inputGamma"]!.GetValue<double>() == 1.8 &&
                sidecar["parameters"]!["baseScale"]!.GetValue<double>() == 1.25,
                "workflow_published_json_uses_frozen_input_values");
            var xmp = System.Xml.Linq.XDocument.Load(ExportArtifactPairing.XmpPath(output));
            System.Xml.Linq.XNamespace ns = ExportSidecarWriter.XmpNamespace;
            Check(xmp.Descendants().Attributes(ns + "InputGamma").Single().Value == "1.8" &&
                xmp.Descendants().Attributes(ns + "BaseScale").Single().Value == "1.25",
                "workflow_published_xmp_uses_frozen_input_values");
            Check(File.ReadAllBytes(source).SequenceEqual(File.ReadAllBytes(ExportArtifactPairing.OriginalPath(output, source))),
                "workflow_original_copy_keeps_source_bytes");
            Check(File.ReadAllText(ExportArtifactPairing.XmpPath(destination)) == "external metadata", "workflow_external_xmp_unchanged");
            Check(ExportArtifactWriter.Write(captured) is not null, "workflow_duplicate_artifacts_fail_visibly");
            Check(!Directory.EnumerateFiles(directory, "*.tmp").Any(), "workflow_no_temporary_sidecars_after_publication");
            string second = Path.Combine(directory, "second.jpg");
            File.WriteAllText(ExportArtifactPairing.SidecarPath(second), "existing json");
            var conflict = captured with { Content = captured.Content with { OutputPath = second }, Settings = settings with { WriteOriginalRaw = false } };
            Check(ExportArtifactWriter.Write(conflict) is not null && File.ReadAllText(ExportArtifactPairing.SidecarPath(second)) == "existing json" &&
                !File.Exists(ExportArtifactPairing.XmpPath(second)), "workflow_existing_json_is_preserved_without_partial_xmp");
        }
        finally { Directory.Delete(directory, recursive: true); }
        VerifyBaseState();
        VerifyPrintCache();
        VerifyOutputDrainAsync().GetAwaiter().GetResult();
    }

    private static void VerifyBaseState()
    {
        var frame = Frame(null) with { AppliedBase = new(0.7, 0.3, 0.2) };
        var state = new DevelopBaseReferenceState();
        state.Bind(frame);
        Check(state.Value == frame.AppliedBase, "workflow_reference_initial_catalog_measurement");
        state.Bind(frame with { Base = frame.Base with { Scale = 1.25 }, AppliedBase = null });
        Check(state.Value == frame.AppliedBase, "workflow_scale_keeps_unscaled_reference");
        state.Bind(frame with { InputGamma = InputGammaInterpretation.Power(2.4), AppliedBase = null });
        Check(state.Value is null, "workflow_new_gamma_does_not_reuse_reference");
        state.Remember(frame, new(0.8, 0.4, 0.3), new(0.7f, 0.3f, 0.2f));
        state.Bind(frame with { Route = frame.Route with { FilmType = FilmType.BlackAndWhiteNegative }, AppliedBase = null });
        Check(state.Value is null, "workflow_process_change_discards_reference");
        state.Bind(null);
        Check(state.Value is null, "workflow_clearing_frame_clears_reference");
    }

    private static void VerifyPrintCache()
    {
        var cache = new PrintPreviewTileCache<string>();
        var key = ("frame", default(PrintPresentationStyle), false, "proof");
        long stale = cache.Revision;
        cache.Clear();
        cache.Store(key, "new gamma pixels");
        Check(!cache.TryStore(stale, key, "old gamma pixels") && cache.TryGetValue(key, out var value) && value == "new gamma pixels",
            "workflow_late_print_decode_cannot_replace_current_recipe");
        Check(cache.TryStore(cache.Revision, key, "current pixels"), "workflow_current_print_decode_is_cached");
        cache.Clear();
        Check(cache.Count == 0, "workflow_print_unload_clears_images");
    }
    private static async Task VerifyOutputDrainAsync()
    {
        var group = new OutputTaskGroup();
        var rendered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var artifacts = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        bool wroteArtifacts = false;
        Task output = group.RunAsync(async () =>
        {
            await rendered.Task;
            await artifacts.Task;
            wroteArtifacts = true;
        });
        bool overlapped = false;
        await group.RunAsync(() => { overlapped = true; return Task.CompletedTask; });
        Check(group.IsRunning && !overlapped, "workflow_artifact_phase_remains_busy_without_duplicate_output");
        Task drain = group.DrainAsync();
        bool unexpectedNewOutput = false;
        await group.RunAsync(() => { unexpectedNewOutput = true; return Task.CompletedTask; });
        Check(!drain.IsCompleted && !unexpectedNewOutput, "workflow_quit_waits_for_output_and_blocks_new_requests");
        rendered.SetResult();
        Check(!drain.IsCompleted, "workflow_quit_waits_for_artifacts_after_image_render");
        artifacts.SetResult();
        await Task.WhenAll(output, drain).WaitAsync(TimeSpan.FromSeconds(5));
        Check(wroteArtifacts && !group.IsRunning, "workflow_quit_finishes_after_artifact_publication");
        try { await group.RunAsync(() => throw new IOException("test output failure")); }
        catch (IOException) { }
        await group.DrainAsync().WaitAsync(TimeSpan.FromSeconds(5));
        bool recovered = false;
        await group.RunAsync(() => { recovered = true; return Task.CompletedTask; });
        Check(recovered, "workflow_failed_output_does_not_strand_shutdown");
    }

}
