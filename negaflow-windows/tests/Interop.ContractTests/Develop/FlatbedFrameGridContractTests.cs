using System.Runtime.InteropServices;

namespace Negaflow.Interop.ContractTests;

internal static unsafe class FlatbedFrameGridContractTests
{
    internal static void Verify(ContractTestContext context)
    {
        context.Check(sizeof(NativeFlatbedFrameGridSummaryV1) == 24,
              "flatbed_summary_size");
        context.Check(sizeof(NativeFlatbedFrameDetectionV1) == 56,
              "flatbed_detection_size");

        const uint width = 640;
        const uint height = 1680;
        float[] luminance = Enumerable.Repeat(0.05f, checked((int)(width * height))).ToArray();
        for (int y = 120; y < 1304; ++y)
        {
            for (int x = 80; x < 272; ++x)
            {
                luminance[y * (int)width + x] = 0.42f +
                    MathF.Sin(x * 0.051f) * MathF.Cos(y * 0.041f) * 0.18f;
            }
        }
        FlatbedFrameGridResult result = NativeFlatbedFrameGridDetector.Detect(
            luminance, width, height, 80.0, 210.0);
        context.Check(result.Status == FlatbedFrameGridStatus.Ok && result.Detections.Count != 0,
              "flatbed_detects_owned_grid");
        context.Check(result.Detections.All(detection =>
                  detection.X >= 0.0 && detection.Y >= 0.0 &&
                  detection.Width > 0.0 && detection.Height > 0.0 &&
                  detection.X + detection.Width <= 1.0 && detection.Y + detection.Height <= 1.0),
              "flatbed_normalized_rectangles");

        using var cancelled = new DevelopRun();
        cancelled.Cancel();
        FlatbedFrameGridResult cancelledResult = NativeFlatbedFrameGridDetector.Detect(
            luminance, width, height, 80.0, 210.0, run: cancelled);
        context.Check(cancelledResult.Status == FlatbedFrameGridStatus.Cancelled &&
                  cancelledResult.Detections.Count == 0,
              "flatbed_cancelled_without_payload");
    }
}
