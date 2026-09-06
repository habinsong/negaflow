using System.Text.Json;
using System.Text.Json.Nodes;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Library;
using Negaflow.Shell.Print;
using static Negaflow.Shell.UnitTests.TestAssert;

namespace Negaflow.Shell.UnitTests;

internal static class InputWorkflowRouteTests
{
    internal static void Run()
    {
        string input = Path.Combine(Path.GetTempPath(), "입력 workflow.tif");
        LibrarySourceMetadata metadata = new(4096, 32, 16, 3, 16, 1, 1);
        foreach (var process in Enum.GetValues<DevelopmentProcess>())
        foreach (bool scanner in new[] { false, true })
        {
            var imported = scanner
                ? FrameImport.PlanScanner(new ScannerFrameImport(input, null, process), [], _ => true, () => "frame", _ => metadata)
                : FrameImport.Plan([input], [], process, _ => true, () => "frame", _ => metadata);
            Check(imported.Rows.Count == 1 && imported.Rejected.Count == 0, "workflow_import_and_scan_produce_valid_frame");
            if (imported.Rows.Count != 1) { continue; }
            var original = imported.Rows[0].Payload;
            var frame = Read(original);
            Check(frame.InputGamma.IsAutomatic && frame.Base.Scale == 1 && frame.DevelopTarget == DevelopTarget.Main,
                "workflow_initial_recipe_uses_auto_input_identity_base_main");
            foreach (double gamma in new[] { 1.8, 2.4 })
            foreach (double scale in new[] { 0.75, 1.25 })
            {
                var record = LibraryFrameWriter.Apply(original, new LibraryFrameEdit(frame.Tone, null, frame.Base with { Scale = scale })
                    { InputGamma = InputGammaInterpretation.Power(gamma) }).FrameRecord!;
                var changed = Read(record);
                foreach (bool raw in new[] { false, true })
                foreach (uint proxy in new[] { 0U, 640U })
                {
                    var request = DevelopRequestFactory.Create(changed, Path.Combine(Path.GetTempPath(), "output.tif"),
                        DevelopExportFormat.Tiff16, uninvertedSource: raw, proxyInputLongEdge: proxy).Request;
                    Check(request is not null && request.InputGammaMode == 1 && request.InputGammaValue == gamma && request.ProxyInputLongEdge == proxy,
                        "workflow_preview_raw_print_export_keep_input_gamma");
                    bool negative = changed.Route.FilmType is FilmType.ColorNegative or FilmType.BlackAndWhiteNegative;
                    Check(request?.BaseScale == (negative ? scale : 1), "workflow_base_scale_only_applies_to_negative_auto_base");
                }
                var flat = ExportFlatMaster.Neutralize(changed);
                Check(flat.InputGamma == changed.InputGamma && flat.Base == changed.Base && flat.DevelopTarget == DevelopTarget.Main,
                    "workflow_flat_master_keeps_input_interpretation");
                byte[] first = DevelopedPreviewCacheRecipeCodec.Compose(DevelopRequestFactory.Create(frame, Path.Combine(Path.GetTempPath(), "out.png")).Request!, null);
                byte[] second = DevelopedPreviewCacheRecipeCodec.Compose(DevelopRequestFactory.Create(changed, Path.Combine(Path.GetTempPath(), "out.png")).Request!, null);
                Check(!first.SequenceEqual(second), "workflow_preview_cache_identity_changes_with_input");
                Check(Read(original).InputGamma.IsAutomatic, "workflow_input_record_is_immutable");
            }
        }
        var preview = FrameImport.PlanScanner(new ScannerFrameImport(input, null, DevelopmentProcess.C41) { IsPreviewScan = true },
            [], _ => true, () => "preview", _ => metadata);
        var previewFrame = Read(preview.Rows.Single().Payload);
        Check(PrintSourceSelection.Eligible([previewFrame]).Count == 0, "workflow_preview_scan_excluded_from_print");
        Check(ExportBatchCoordinator.Plan([previewFrame], new ExportSettings()).Count == 0, "workflow_preview_scan_excluded_from_export");
        var exporter = new FakeExporter(_ => throw new InvalidOperationException("Preview scan must not export"));
        var coordinator = new DevelopExportCoordinator(exporter, new FakeDispatcher(true));
        DevelopExportOutcome? outcome = null;
        coordinator.StartAsync(previewFrame, Path.Combine(Path.GetTempPath(), "preview-output.tif"),
            DevelopExportFormat.Tiff16, value => outcome = value).GetAwaiter().GetResult();
        Check(outcome?.Kind == DevelopExportOutcomeKind.Refused && exporter.CallCount == 0 && !coordinator.IsRunning,
            "workflow_direct_preview_export_is_refused_before_native_call");
    }
    private static LibraryFrameSnapshot Read(JsonObject record) => LibraryFrameReader.Read(JsonSerializer.SerializeToElement(record)).Frame!;
}
