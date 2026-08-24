using System.Diagnostics;
using System.Text.Json;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// Auto/Guided의 실제 최초 응답인 검출→review state→overlay byte 생성을 반복 측정합니다.
/// WinUI WriteableBitmap/Composition 제출은 이 경계 밖입니다.
/// </summary>
internal static class GrainMendDetectionOverlayDiagnostics
{
    private static readonly DefectRect WholeFrame = new(0.0, 0.0, 1.0, 1.0);
    private static readonly DefectRect GuidedRoi = new(0.25, 0.25, 0.5, 0.5);

    private sealed record Sample(
        double Milliseconds,
        int ComponentCount,
        string? ReviewSha256,
        string? OverlaySha256,
        string? Failure);

    private sealed record Scenario(
        string Tool,
        double TargetMilliseconds,
        Sample Warmup,
        IReadOnlyList<double> SamplesMilliseconds,
        int ComponentCount,
        string? ReviewSha256,
        string? OverlaySha256,
        GrainMendLatencySummary Latency,
        bool AllSucceeded,
        bool ComponentCountStable,
        bool ReviewStable,
        bool OverlayStable,
        bool MeetsTarget);

    public static bool TryRun(string[] args, out int exitCode)
    {
        exitCode = 0;
        if (args.Length == 0 || args[0] != "--grainmend-detect-overlay-p95")
        {
            return false;
        }
        if (args.Length is < 3 or > 5 ||
            !int.TryParse(args.ElementAtOrDefault(3) ?? "20", out int iterations) ||
            iterations is < 20 or > 100 ||
            !double.TryParse(args.ElementAtOrDefault(4) ?? "1500", out double canvasPixels) ||
            !double.IsFinite(canvasPixels) || canvasPixels <= 0.0)
        {
            Console.Error.WriteLine(
                "usage: --grainmend-detect-overlay-p95 <storageRoot> <frameSelector> " +
                "[iterations=20] [canvasPixels=1500]");
            exitCode = 2;
            return true;
        }

        exitCode = Run(args[1], args[2], iterations, canvasPixels);
        return true;
    }

    private static int Run(
        string storageRoot,
        string frameSelector,
        int iterations,
        double canvasPixels)
    {
        if (StorageRootResolver.ResolveForTests(Path.GetFullPath(storageRoot)).Roots is not
            { } roots)
        {
            Console.Error.WriteLine("storage root refused");
            return 2;
        }

        Environment.SetEnvironmentVariable("NEGA_TIMING", "1");
        using PumpDispatcher dispatcher = new();
        using LibraryHostService host = new(dispatcher);
        if (host.Open(roots) != LibraryHostState.Open)
        {
            Console.Error.WriteLine("catalog refused");
            return 2;
        }
        if (host.Frames.FirstOrDefault(candidate =>
                candidate.SourcePath.Contains(frameSelector, StringComparison.OrdinalIgnoreCase) &&
                File.Exists(candidate.SourcePath)) is not { } selected)
        {
            Console.Error.WriteLine("frame unavailable");
            return 2;
        }
        LibraryFrameSnapshot frame = selected with
        {
            DefectRecipe = null,
            DefectRecipeRevision = 0UL,
            DefectReviewMark = null,
        };

        NativeDevelopExporterAdapter exporter = new();
        PreviewCoordinator preview = new(exporter, dispatcher, () => canvasPixels);
        GrainMendPreviewLatency warmPreview =
            GrainMendPreviewLatencyProbe.Measure(dispatcher, preview, frame);
        if (warmPreview.Failure is not null || warmPreview.Width == 0U || warmPreview.Height == 0U)
        {
            Console.Error.WriteLine("baseline preview warm-up failed");
            return 1;
        }

        GrainMendDetectCoordinator detector = new(exporter, dispatcher);
        Scenario automatic = RunScenario(
            "automatic-detect-overlay",
            targetMilliseconds: 5000.0,
            frame,
            WholeFrame,
            automatic: true,
            iterations,
            warmPreview.Width,
            warmPreview.Height,
            detector);
        Scenario guided = RunScenario(
            "guided-detect-overlay",
            targetMilliseconds: 1000.0,
            frame,
            GuidedRoi,
            automatic: false,
            iterations,
            warmPreview.Width,
            warmPreview.Height,
            detector);
        Scenario[] scenarios = [automatic, guided];
        bool passed = scenarios.All(Approved);
        Console.WriteLine(JsonSerializer.Serialize(new
        {
            status = passed ? "ok" : "failed",
            operation = "grainmend_detect_overlay_p95",
            evidenceBoundary = "Shell.Core input to detection review overlay bytes; not WinUI WriteableBitmap or composition",
            adapterEvidence = "same-process [timing] gpu adapter line on stderr at process exit",
            source = Path.GetFileName(frame.SourcePath),
            sourcePixels = frame.SourceMetadata is { } metadata
                ? $"{metadata.PixelWidth}x{metadata.PixelHeight}"
                : "unknown",
            previewPixels = $"{warmPreview.Width}x{warmPreview.Height}",
            iterations,
            percentile = "nearest-rank p95",
            canvasPixels,
            warmPreview,
            scenarios,
        }, new JsonSerializerOptions { WriteIndented = true }));
        return passed ? 0 : 1;
    }

    private static Scenario RunScenario(
        string tool,
        double targetMilliseconds,
        LibraryFrameSnapshot frame,
        DefectRect roi,
        bool automatic,
        int iterations,
        uint previewWidth,
        uint previewHeight,
        GrainMendDetectCoordinator detector)
    {
        Sample warmup = Measure(
            frame, roi, automatic, previewWidth, previewHeight, detector);
        List<Sample> samples = new(iterations);
        for (int index = 0; index < iterations; ++index)
        {
            samples.Add(Measure(
                frame, roi, automatic, previewWidth, previewHeight, detector));
        }

        bool allSucceeded = warmup.Failure is null &&
            samples.All(sample => sample.Failure is null);
        bool componentCountStable = samples.All(sample =>
            sample.ComponentCount == warmup.ComponentCount);
        bool reviewStable = Stable(
            warmup.ReviewSha256,
            samples.Select(sample => sample.ReviewSha256));
        bool overlayStable = Stable(
            warmup.OverlaySha256,
            samples.Select(sample => sample.OverlaySha256));
        GrainMendLatencySummary latency = GrainMendPerformanceStatistics.Summarize(
            samples.Select(sample => sample.Milliseconds));
        return new Scenario(
            tool,
            targetMilliseconds,
            warmup,
            samples.Select(sample => Math.Round(sample.Milliseconds, 1)).ToArray(),
            warmup.ComponentCount,
            warmup.ReviewSha256,
            warmup.OverlaySha256,
            latency,
            allSucceeded,
            componentCountStable,
            reviewStable,
            overlayStable,
            latency.P95Milliseconds <= targetMilliseconds);
    }

    private static Sample Measure(
        LibraryFrameSnapshot frame,
        DefectRect roi,
        bool automatic,
        uint previewWidth,
        uint previewHeight,
        GrainMendDetectCoordinator detector)
    {
        GrainMendWorkspaceState state = new();
        using DevelopRun run = new();
        using ManualResetEventSlim completed = new();
        int components = 0;
        string? reviewSha = null;
        string? overlaySha = null;
        string? failure = null;
        Stopwatch clock = Stopwatch.StartNew();
        long generation = state.BeginDetection(
            frame.Id,
            run,
            automatic ? DefectEditLabelKind.Automatic : DefectEditLabelKind.Guided);
        bool delivered;
        try
        {
            delivered = detector.RunAsync(
                frame,
                roi,
                GrainMendSensitivity.ToDetectionOptions(
                    GrainMendSensitivity.Default,
                    automatic),
                outcome =>
                {
                    bool disposeOutcome = true;
                    try
                    {
                        if (outcome.Kind != DevelopExportOutcomeKind.Completed)
                        {
                            failure = outcome.FaultMessage ?? outcome.Refusal.ToString();
                            return;
                        }
                        if (outcome.ReviewProposal is null ||
                            outcome.DetectionToken is not { } token)
                        {
                            failure = "detection found no reviewable components";
                            return;
                        }

                        disposeOutcome = false;
                        if (!state.SetDetectedReview(
                                outcome.ReviewProposal,
                                token,
                                frame.Id,
                                generation,
                                roi,
                                automatic,
                                outcome.AutomaticFalsePositiveRisk) ||
                            state.PendingEdit is not { } edit ||
                            state.PendingReview is not { } review)
                        {
                            failure = "review state refused detection";
                            return;
                        }
                        byte[]? overlay = GrainMendOverlayRenderer.Render(
                            frame,
                            checked((int)previewWidth),
                            checked((int)previewHeight),
                            edit,
                            review);
                        if (overlay is null)
                        {
                            failure = "overlay renderer returned no pixels";
                            return;
                        }
                        components = review.ComponentCount;
                        reviewSha = GrainMendQualitySignature.FromEdit(edit);
                        overlaySha = GrainMendQualitySignature.FromPixels(overlay);
                    }
                    catch (Exception error)
                    {
                        failure = error.GetType().Name;
                    }
                    finally
                    {
                        if (disposeOutcome)
                        {
                            outcome.Dispose();
                        }
                        clock.Stop();
                        completed.Set();
                    }
                },
                run).GetAwaiter().GetResult();
        }
        catch (Exception error)
        {
            clock.Stop();
            failure = error.GetType().Name;
            delivered = false;
        }
        if (!delivered && failure is null)
        {
            clock.Stop();
            failure = "dispatcher refused detection outcome";
        }
        if (failure is null && !completed.Wait(TimeSpan.FromSeconds(120)))
        {
            clock.Stop();
            failure = "detection overlay timeout";
        }
        state.EndDetection(frame.Id, generation);
        state.ClearPending();
        return new Sample(
            clock.Elapsed.TotalMilliseconds,
            components,
            reviewSha,
            overlaySha,
            failure);
    }

    private static bool Stable(string? expected, IEnumerable<string?> values) =>
        expected is not null && values.All(value =>
            string.Equals(expected, value, StringComparison.Ordinal));

    private static bool Approved(Scenario scenario) =>
        scenario.AllSucceeded && scenario.ComponentCountStable &&
        scenario.ReviewStable && scenario.OverlayStable && scenario.MeetsTarget;
}
