using System.Runtime.InteropServices;

namespace Negaflow.Interop.ContractTests;

internal static unsafe class InfraredDetectorContractTests
{
    internal static void Verify(ContractTestContext context)
    {
        context.Check(sizeof(NativeInfraredDetectorParametersV1) ==
              NativeInfraredDefectDetector.ParametersV1Size, "infrared_parameters_size");
        context.Check(sizeof(NativeInfraredDetectionSummaryV1) ==
              NativeInfraredDefectDetector.SummaryV1Size, "infrared_summary_size");
        context.Check(sizeof(NativeInfraredClusterV1) ==
              NativeInfraredDefectDetector.ClusterV1Size, "infrared_cluster_size");
        context.Check(sizeof(NativeInfraredComponentV1) ==
              NativeInfraredDefectDetector.ComponentV1Size, "infrared_component_size");

        const uint width = 128;
        const uint height = 96;
        float[] infrared = Enumerable.Repeat(0.8f, checked((int)(width * height))).ToArray();
        float[] red = Enumerable.Repeat(0.7f, infrared.Length).ToArray();
        for (int y = 44; y <= 52; ++y)
        {
            for (int x = 58; x <= 66; ++x)
            {
                int dx = x - 62;
                int dy = y - 48;
                if (dx * dx + dy * dy <= 16)
                {
                    infrared[y * (int)width + x] = 0.48f;
                    red[y * (int)width + x] = 0.42f;
                }
            }
        }
        InfraredDetectionResult result = NativeInfraredDefectDetector.Detect(
            infrared,
            red,
            width,
            height,
            new InfraredDetectorParameters { AlignmentSearchRadius = 0 });
        context.Check(result.Status == InfraredDetectionStatus.Ok, "infrared_detect_status");
        context.Check(result.Clusters.Count >= 1 && result.Components.Count >= 1,
              "infrared_owned_payload_copied");
        context.Check(result.Clusters[0].AttenuationR16.Length ==
              checked((int)(result.Clusters[0].Width * result.Clusters[0].Height * 2U)),
              "infrared_attenuation_shape");

        using var cancelled = new DevelopRun();
        cancelled.Cancel();
        InfraredDetectionResult cancelledResult = NativeInfraredDefectDetector.Detect(
            infrared, red, width, height, run: cancelled);
        context.Check(cancelledResult.Status == InfraredDetectionStatus.Cancelled,
              "infrared_cancelled_without_payload");

        string missingVisible = Path.Combine(AppContext.BaseDirectory, "missing-visible.tiff");
        string missingInfrared = Path.Combine(AppContext.BaseDirectory, "missing-infrared.tiff");
        InfraredDetectionResult unreadableFiles = NativeInfraredDefectDetector.DetectFiles(
            missingVisible, missingInfrared);
        context.Check(unreadableFiles.Status == InfraredDetectionStatus.Unreadable,
              "infrared_tiff_entry_point_reports_unreadable_pair");
        InfraredDetectionResult cancelledFiles = NativeInfraredDefectDetector.DetectFiles(
            missingVisible, missingInfrared, run: cancelled);
        context.Check(cancelledFiles.Status == InfraredDetectionStatus.Cancelled,
              "infrared_tiff_entry_point_cancels_before_decode");
    }
}
