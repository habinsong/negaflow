using System.Diagnostics;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell.UnitTests;

internal sealed record GrainMendPreviewLatency(
    double? InteractiveMilliseconds,
    double? SettledMilliseconds,
    uint Width,
    uint Height,
    string? InteractivePixelSha256,
    string? SettledPixelSha256,
    string? Failure);

internal static class GrainMendPreviewLatencyProbe
{
    public static GrainMendPreviewLatency Measure(
        PumpDispatcher dispatcher,
        PreviewCoordinator coordinator,
        LibraryFrameSnapshot frame)
    {
        object sync = new();
        using ManualResetEventSlim completed = new();
        Stopwatch clock = Stopwatch.StartNew();
        double? interactiveMilliseconds = null;
        double? settledMilliseconds = null;
        string? interactiveHash = null;
        string? settledHash = null;
        uint width = 0U;
        uint height = 0U;
        string? failure = null;

        dispatcher.Send(() => _ = coordinator.RequestAsync(frame, outcome =>
        {
            lock (sync)
            {
                if (outcome.Kind != DevelopExportOutcomeKind.Completed ||
                    outcome.Result is not { Succeeded: true } ||
                    outcome.Pixels is not { Length: > 0 } pixels)
                {
                    failure ??= outcome.FaultMessage ?? outcome.Result?.FailureName ??
                        outcome.Refusal.ToString();
                    completed.Set();
                    return;
                }

                double elapsed = clock.Elapsed.TotalMilliseconds;
                string hash = GrainMendQualitySignature.FromPixels(pixels);
                width = outcome.Width;
                height = outcome.Height;
                if (!outcome.Settled)
                {
                    interactiveMilliseconds ??= elapsed;
                    interactiveHash ??= hash;
                    return;
                }

                settledMilliseconds = elapsed;
                settledHash = hash;
                completed.Set();
            }
        }));

        if (!completed.Wait(TimeSpan.FromSeconds(120)))
        {
            failure = "preview timeout";
        }
        lock (sync)
        {
            return new GrainMendPreviewLatency(
                interactiveMilliseconds,
                settledMilliseconds,
                width,
                height,
                interactiveHash,
                settledHash,
                failure);
        }
    }
}
