using System.Text.Json.Nodes;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using static Negaflow.Shell.UnitTests.TestAssert;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// macOS <c>Sidecar.FilmBaseDiagnostics</c> 를 shipped <see cref="ExportSidecarWriter"/> 가
/// 그대로 쓰는지 봅니다. 수동은 신뢰도를 만들지 않습니다.
/// </summary>
internal static class FilmBaseSidecarTests
{
    public static void Run()
    {
        VerifyMeasuredSidecarCarriesEvidence();
        VerifyManualSidecarDoesNotInventConfidence();
    }

    private static void VerifyMeasuredSidecarCarriesEvidence()
    {
        FilmBaseMeasurementSnapshot measurement = new()
        {
            SchemaVersion = 1,
            Method = "connectedComponent",
            SampledPixelCount = 43776,
            CandidateCount = 200,
            SelectedSampleCount = 100,
            RetainedSampleCount = 96,
            SampleCoverage = 0.02,
            SpatialCoverage = 0.8,
            MedianLuma = 0.14,
            LumaMad = 0.01,
            ChannelMad = [0.01, 0.01, 0.01],
            ChromaticityMad = 0.002,
            ClippedFraction = 0,
            OutlierFraction = 0.04,
            SampleSupport = 1,
            EvidenceSampleCoverage = 1,
            EvidenceSpatialCoverage = 0.8,
            LumaUniformity = 0.9,
            ChannelConsistency = 0.95,
            UnclippedSamples = 1,
            InlierRetention = 0.96,
            EvidenceScore = 0.729107,
            IsCalibratedProbability = false,
            Anomalies = [],
        };
        FilmBaseDiagnosticsSidecar diagnostics = FilmBaseDiagnosticsSidecar.From(
            0.22128,
            0.13298,
            0.0710158,
            FilmBaseDiagnosticsSidecar.SourceName(
                DevelopBaseSource.AutoConnectedComponent,
                measurement.Method),
            measurement);
        Check(
            diagnostics.Source == "auto",
            "measured_sidecar_source_is_auto_for_connected_component");
        Check(
            diagnostics.Confidence == 0.729107,
            "measured_sidecar_confidence_is_evidence_score");
        Check(
            diagnostics.ConfidenceBasis == FilmBaseMeasurementSnapshot.ConfidenceBasis,
            "measured_sidecar_basis_is_measured_evidence_score_v1");
        Check(
            diagnostics.ConfidenceIsCalibratedProbability == false,
            "measured_sidecar_is_not_a_calibrated_probability");
        Check(
            Math.Abs(diagnostics.Dmin[0] - (-Math.Log10(0.22128))) < 1.0e-12,
            "measured_sidecar_dmin_is_minus_log10");

        string json = ExportSidecarWriter.BuildJson(Content(diagnostics, FilmBaseDiagnosticsSidecar.Sample(
            0.22128,
            0.13298,
            0.0710158,
            "auto")));
        JsonNode root = JsonNode.Parse(json)!;
        Check(
            root["filmBaseDiagnostics"]?["confidence"]?.GetValue<double>() == 0.729107,
            "writer_emits_confidence_from_evidence_score");
        Check(
            root["filmBaseDiagnostics"]?["confidenceBasis"]?.GetValue<string>() ==
            "measuredEvidenceScoreV1",
            "writer_emits_measured_evidence_score_v1");
        Check(
            root["filmBaseDiagnostics"]?["measurement"]?["method"]?.GetValue<string>() ==
            "connectedComponent",
            "writer_nests_the_measurement_method");
        Check(
            root["filmBaseDiagnostics"]?["measurement"]?["sampledPixelCount"]?.GetValue<int>() ==
            43776,
            "writer_nests_sampled_pixel_count");
        Check(
            root["baseSample"]?["source"]?.GetValue<string>() == "auto",
            "writer_emits_base_sample_source");
        Check(
            FilmBaseDiagnosticsSidecar.SourceName(
                DevelopBaseSource.AutoContinuousBorder,
                "continuousBorder") == "border",
            "border_method_maps_to_border_source");
        Check(
            FilmBaseDiagnosticsSidecar.SourceName(
                DevelopBaseSource.AutoStripFallback,
                "stripFallback") == "border",
            "strip_fallback_maps_to_border_source");
    }

    private static void VerifyManualSidecarDoesNotInventConfidence()
    {
        FilmBaseDiagnosticsSidecar diagnostics = FilmBaseDiagnosticsSidecar.From(
            0.72,
            0.52,
            0.34,
            FilmBaseDiagnosticsSidecar.SourceName(DevelopBaseSource.Manual, null),
            null);
        Check(diagnostics.Source == "manual", "manual_sidecar_source_is_manual");
        Check(diagnostics.Confidence is null, "manual_sidecar_has_no_confidence");
        Check(diagnostics.ConfidenceBasis is null, "manual_sidecar_has_no_confidence_basis");
        Check(diagnostics.Measurement is null, "manual_sidecar_has_no_measurement");

        string json = ExportSidecarWriter.BuildJson(Content(
            diagnostics,
            FilmBaseDiagnosticsSidecar.Sample(0.72, 0.52, 0.34, "manual")));
        JsonNode root = JsonNode.Parse(json)!;
        Check(
            root["filmBaseDiagnostics"]?["confidence"] is null,
            "writer_does_not_invent_manual_confidence");
        Check(
            root["filmBaseDiagnostics"]?["confidenceBasis"] is null,
            "writer_does_not_invent_manual_confidence_basis");
        Check(
            root["filmBaseDiagnostics"]?["measurement"] is null,
            "writer_does_not_invent_manual_measurement");
        Check(
            root["baseSample"]?["source"]?.GetValue<string>() == "manual",
            "writer_marks_manual_base_sample");

        string xmp = ExportSidecarWriter.BuildXmp(Content(
            diagnostics,
            FilmBaseDiagnosticsSidecar.Sample(0.72, 0.52, 0.34, "manual")));
        Check(
            xmp.Contains("negaflow:BaseSampleSource=\"manual\"", StringComparison.Ordinal),
            "xmp_carries_base_sample_source");
    }

    private static ExportSidecarContent Content(
        FilmBaseDiagnosticsSidecar diagnostics,
        FilmBaseSampleSidecar sample) =>
        new()
        {
            OutputPath = @"D:\Export\IMG_0007.tif",
            Format = DevelopExportFormat.Jpeg8,
            Encoding = new ExportSettings().ToEncodingOptions(),
            FilmBaseDiagnostics = diagnostics,
            BaseSample = sample,
            ExportedAt = new DateTimeOffset(2026, 8, 19, 5, 0, 0, TimeSpan.Zero),
        };
}
