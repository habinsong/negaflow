using System.Runtime.InteropServices;

namespace Negaflow.Interop.ContractTests;

internal static unsafe class FlatbedFrameGridContractTests
{
    internal static void Verify(ContractTestContext context)
    {
        context.Check(sizeof(NativeFlatbedFrameGridSummaryV1) == 24,
              "flatbed_summary_size");
        context.Check(sizeof(NativeFlatbedFrameDetectionV1) == 64,
              "flatbed_detection_size");
        context.Check(sizeof(NativeFlatbedFrameDimensionsV1) == 32,
              "flatbed_dimensions_size");

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

        // 치수 입구는 같은 검출기를 부릅니다. 36×24(35mm)를 치수로 넘기면 규격과 같은 답입니다.
        FlatbedFrameGridResult sized = NativeFlatbedFrameGridDetector.Detect(
            luminance, width, height, 80.0, 210.0, new FlatbedFrameDimensions(36.0, 24.0, true));
        context.Check(sized.Status == FlatbedFrameGridStatus.Ok &&
                  sized.Detections.SequenceEqual(result.Detections),
              "flatbed_dimensions_match_the_preset");
        FlatbedFrameGridResult panorama = NativeFlatbedFrameGridDetector.Detect(
            luminance, width, height, 80.0, 210.0, FlatbedFrameFormat.Panorama35mm65x24);
        context.Check(panorama.Status == FlatbedFrameGridStatus.Ok,
              "flatbed_accepts_panorama_format");
        FlatbedFrameGridResult sizedEdges = NativeFlatbedFrameGridDetector.DetectEdges(
            luminance, width, height, new FlatbedFrameDimensions(58.0, 24.0, true));
        context.Check(sizedEdges.Status == FlatbedFrameGridStatus.Ok,
              "flatbed_edge_dimensions_call");
        bool refused = false;
        try
        {
            _ = NativeFlatbedFrameGridDetector.Detect(
                luminance, width, height, 80.0, 210.0,
                new FlatbedFrameDimensions(double.NaN, 24.0, true));
        }
        catch (ArgumentOutOfRangeException)
        {
            refused = true;
        }
        context.Check(refused, "flatbed_dimensions_refuse_nan");

        using var cancelled = new DevelopRun();
        cancelled.Cancel();
        FlatbedFrameGridResult cancelledResult = NativeFlatbedFrameGridDetector.Detect(
            luminance, width, height, 80.0, 210.0, run: cancelled);
        context.Check(cancelledResult.Status == FlatbedFrameGridStatus.Cancelled &&
                  cancelledResult.Detections.Count == 0,
              "flatbed_cancelled_without_payload");
    }
}
