using System.Text.Json;
using System.Text.Json.Nodes;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Print;
using static Negaflow.Shell.UnitTests.TestAssert;
using static Negaflow.Shell.UnitTests.TestFrameFactory;

namespace Negaflow.Shell.UnitTests;

internal static class InputWorkflowRegressionTests
{
    internal static void Run()
    {
        VerifyImportFailure();
        VerifyBaseInvalidation();
        VerifySidecarPreservation();
    }

    private static void VerifyImportFailure()
    {
        string path = Path.Combine(Path.GetTempPath(), "workflow-source.tif");
        foreach (LibrarySourceMetadata? metadata in new LibrarySourceMetadata?[] { null, default(LibrarySourceMetadata) })
        {
            var scan = FrameImport.PlanScanner(new ScannerFrameImport(path, null, DevelopmentProcess.C41), [],
                _ => true, () => "scan", _ => metadata);
            Check(scan.Rows.Count == 0 && scan.Rejected.Any(r => r.Refusal == FrameImportRefusal.UndecodableImage),
                "workflow_scanner_rejects_unreadable_metadata");
            var imported = FrameImport.Plan([path], [], DevelopmentProcess.C41, _ => true, () => "import", _ => metadata);
            Check(imported.Rows.Count == 0 && imported.Rejected.Any(r => r.Refusal == FrameImportRefusal.UndecodableImage),
                "workflow_import_rejects_invalid_metadata");
        }
    }

    private static void VerifyBaseInvalidation()
    {
        var record = FrameRecord("frame", "source.tif", 0);
        record["rawScanPath"] = Path.Combine(Path.GetTempPath(), "workflow-source.tif");
        record["params"]!.AsObject().Remove("manualBaseRGB");
        record["params"]!["baseEstimationMode"] = "auto";
        record["baseRGB"] = new JsonArray(0.7, 0.3, 0.2);
        var frame = LibraryFrameReader.Read(JsonSerializer.SerializeToElement(record)).Frame!;
        var gamma = LibraryFrameWriter.Apply(record, new LibraryFrameEdit(frame.Tone, null, frame.Base)
            { InputGamma = InputGammaInterpretation.Power(1.8) }).FrameRecord!;
        Check(!gamma.ContainsKey("baseRGB"), "workflow_gamma_change_discards_previous_measured_base");
        var scale = LibraryFrameWriter.Apply(record, new LibraryFrameEdit(frame.Tone, null, frame.Base with { Scale = 1.25 })).FrameRecord!;
        Check(!scale.ContainsKey("baseRGB"), "workflow_scale_change_discards_previous_applied_base");
        var tone = LibraryFrameWriter.Apply(record, new LibraryFrameEdit(frame.Tone with { Exposure = 0.5 }, null, frame.Base)).FrameRecord!;
        Check(JsonNode.DeepEquals(tone["baseRGB"], record["baseRGB"]), "workflow_tone_edit_preserves_measured_base");
        var route = DevelopRouteWriter.Apply(record, DevelopRouteSelection.FromProcess(DevelopmentProcess.D76)).FrameRecord!;
        Check(!route.ContainsKey("baseRGB"), "workflow_process_change_discards_previous_measured_base");
        Check(record["baseRGB"] is not null, "workflow_invalidation_does_not_mutate_source_record");
        var versioned = LibraryVersions.Capture(record, "before", "before", DateTimeOffset.UnixEpoch).FrameRecord!;
        versioned["params"]!["inputGamma"] = 1.8;
        var restored = LibraryVersions.Restore(versioned, "before").FrameRecord!;
        Check(!restored.ContainsKey("baseRGB") && restored["params"]!["inputGamma"] is null,
            "workflow_version_restore_invalidates_previous_input_base");
    }

    private static void VerifySidecarPreservation()
    {
        string directory = Path.Combine(Path.GetTempPath(), "negaflow-workflow-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        try
        {
            string output = Path.Combine(directory, "scan.jpg");
            string xmp = ExportArtifactPairing.XmpPath(output);
            File.WriteAllText(xmp, "external source xmp");
            var content = new ExportSidecarContent { OutputPath = output, Format = DevelopExportFormat.Jpeg8,
                Encoding = ExportEncodingOptions.Default, Parameters = new JsonObject { ["inputGamma"] = 1.8, ["baseScale"] = 1.25 } };
            var result = ExportSidecarWriter.Write(output, content);
            Check(result is not null && File.ReadAllText(xmp) == "external source xmp", "workflow_never_overwrites_external_xmp");
            Check(!File.Exists(ExportArtifactPairing.SidecarPath(output)), "workflow_existing_xmp_does_not_create_partial_json");
        }
        finally { Directory.Delete(directory, recursive: true); }
    }
}
