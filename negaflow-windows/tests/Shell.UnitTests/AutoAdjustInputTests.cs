using Negaflow.Catalog;
using Negaflow.Interop;
using static Negaflow.Shell.UnitTests.TestAssert;
using static Negaflow.Shell.UnitTests.TestFrameFactory;
using static Negaflow.Shell.UnitTests.DevelopTestResults;

namespace Negaflow.Shell.UnitTests;

internal static class AutoAdjustInputTests
{
    public static void Run()
    {
        VerifyConcurrentBuffers().GetAwaiter().GetResult();
        VerifyQueuedCancellationAndInputMatrix().GetAwaiter().GetResult();
        VerifyFailureBoundaries().GetAwaiter().GetResult();
    }

    private static async Task VerifyFailureBoundaries()
    {
        var exporter = new PixelExporter((_, _) => OkResult());
        var coordinator = new AutoAdjustCoordinator(exporter, new FakeDispatcher(true), 128, (_, _, _) => Settings(0));
        var source = Frame(null) with { SourcePath = Path.Combine(Path.GetTempPath(), "auto-errors.tif") };
        var outcomes = new List<AutoAdjustOutcome>();
        bool escaped = false;
        try { await coordinator.RunToneAsync(source with { ColorModel = null! }, outcomes.Add); }
        catch (NullReferenceException) { escaped = true; }
        Check(!escaped && outcomes is [{ Kind: DevelopExportOutcomeKind.Faulted }] && !coordinator.IsRunning,
            "auto_invalid_request_clears_running_and_reports_failure");
        int callbacks = 0;
        try
        {
            await coordinator.RunToneAsync(source, _ => { callbacks++; throw new InvalidOperationException("callback failure"); });
        }
        catch (InvalidOperationException) { }
        Check(callbacks == 1 && !coordinator.IsRunning, "auto_callback_exception_is_not_delivered_twice");
        outcomes.Clear();
        await coordinator.RunToneAsync(source, outcomes.Add);
        Check(outcomes is [{ Kind: DevelopExportOutcomeKind.Completed }] && !coordinator.IsRunning,
            "auto_recovers_after_request_and_callback_failures");
    }

    private static async Task VerifyConcurrentBuffers()
    {
        using var firstStarted = new ManualResetEventSlim(false);
        using var secondFinished = new ManualResetEventSlim(false);
        byte firstValue = 0;
        var exporter = new PixelExporter((request, pixels) =>
        {
            if (request.InputGammaValue == 1.8)
            {
                pixels[0] = 18; firstStarted.Set();
                if (!secondFinished.Wait(TimeSpan.FromSeconds(5))) { throw new TimeoutException(); }
                firstValue = pixels[0];
            }
            else { pixels[0] = 24; secondFinished.Set(); }
            return OkResult();
        });
        var coordinator = new AutoAdjustCoordinator(exporter, new FakeDispatcher(true), 128,
            (pixels, _, _) => Settings(pixels[0] / 100.0));
        var first = Frame(new ManualBaseRgb(0.7, 0.3, 0.2)) with
        { SourcePath = Path.Combine(Path.GetTempPath(), "auto-input.tif"), InputGamma = InputGammaInterpretation.Power(1.8) };
        List<double> delivered = [];
        var task = coordinator.RunToneAsync(first, outcome => delivered.Add(outcome.Settings!.Exposure));
        Check(firstStarted.Wait(TimeSpan.FromSeconds(5)), "auto_first_render_started");
        Check(coordinator.IsRunning, "auto_running_during_render");
        await coordinator.RunToneAsync(first with { InputGamma = InputGammaInterpretation.Power(2.4) },
            outcome => delivered.Add(outcome.Settings!.Exposure));
        await task;
        Check(firstValue == 18, "auto_requests_never_share_pixel_buffer");
        Check(delivered.SequenceEqual([0.24]) && !coordinator.IsRunning, "auto_only_latest_request_delivers");
    }

    private static async Task VerifyQueuedCancellationAndInputMatrix()
    {
        var dispatcher = new QueuedDispatcher();
        var source = Frame(null) with { SourcePath = Path.Combine(Path.GetTempPath(), "auto-matrix.tif") };
        DevelopExportRequest? observed = null;
        var exporter = new PixelExporter((request, pixels) => { observed = request; pixels[0] = 18; return OkResult(); });
        var coordinator = new AutoAdjustCoordinator(exporter, dispatcher, 128, (_, _, _) => Settings(0.18));
        var outcomes = new List<AutoAdjustOutcome>();
        foreach (double gamma in new[] { 0.0, 1.8, 2.4 })
        foreach (double scale in new[] { 0.75, 1.25 })
        foreach (bool levels in new[] { false, true })
        foreach (bool color in new[] { false, true })
        {
            var frame = source with { InputGamma = gamma == 0 ? InputGammaInterpretation.Automatic : InputGammaInterpretation.Power(gamma),
                Base = BaseRecipe.Auto with { Scale = scale }, AutoLevels = levels, AutoNeutralBalance = color };
            await coordinator.RunToneAsync(frame, outcomes.Add);
            Check(observed?.InputGammaValue == gamma && observed.BaseScale == scale &&
                observed.AutoLevels == levels && observed.AutoNeutralBalance == color, "auto_tone_request_keeps_input_and_toggle_matrix");
            dispatcher.Drain();
            var tone = outcomes[^1].Frame!;
            Check(tone.InputGamma == frame.InputGamma && tone.Base == frame.Base &&
                tone.AutoLevels == levels && tone.AutoNeutralBalance == color, "auto_tone_result_keeps_input_and_toggles");
            await coordinator.RunWhiteBalanceAsync(frame, outcomes.Add);
            dispatcher.Drain();
            Check(outcomes[^1].Frame!.InputGamma == frame.InputGamma && outcomes[^1].Frame!.Base == frame.Base,
                "auto_wb_result_keeps_input_and_scale");
        }
        outcomes.Clear();
        await coordinator.RunToneAsync(source, outcomes.Add);
        coordinator.Cancel();
        dispatcher.Drain();
        Check(outcomes.Count == 0 && !coordinator.IsRunning, "auto_cancel_suppresses_queued_callback");
        await coordinator.RunToneAsync(source, outcomes.Add);
        await coordinator.RunWhiteBalanceAsync(source, outcomes.Add);
        dispatcher.Drain();
        Check(outcomes.Count == 1 && !coordinator.IsRunning, "auto_new_request_suppresses_previous_queued_callback");
        var cancelled = new AutoAdjustCoordinator(new PixelExporter((_, _) => throw new OperationCanceledException()), dispatcher, 128,
            (_, _, _) => Settings(0));
        outcomes.Clear();
        await cancelled.RunToneAsync(source, outcomes.Add);
        dispatcher.Drain();
        Check(outcomes is [{ Kind: DevelopExportOutcomeKind.Cancelled }] && !cancelled.IsRunning,
            "auto_cancellation_is_not_fault_or_unhandled_task");
        var tooSmall = new AutoAdjustCoordinator(exporter, dispatcher, 1, (_, _, _) => throw new InvalidOperationException("Must not compute"));
        outcomes.Clear();
        await tooSmall.RunToneAsync(source, outcomes.Add);
        dispatcher.Drain();
        Check(outcomes is [{ Kind: DevelopExportOutcomeKind.Faulted }] && !tooSmall.IsRunning,
            "auto_rejects_preview_dimensions_larger_than_buffer");
    }

    private sealed class QueuedDispatcher : IUiDispatcher
    {
        private readonly Queue<Action> actions = new();
        public bool HasThreadAccess => false;
        public bool TryEnqueue(Action action) { lock (actions) { actions.Enqueue(action); } return true; }
        public void Drain()
        {
            while (true)
            {
                Action? action;
                lock (actions) { if (!actions.TryDequeue(out action)) { return; } }
                action();
            }
        }
    }

    private static AutoAdjustSettings Settings(double value) => new(value, 0, 0, 0, 0, 0, 0, 0, 0, 0);

    private sealed class PixelExporter(Func<DevelopExportRequest, byte[], DevelopExportResult> preview) : IDevelopExporter
    {
        public DevelopExportResult Preview(DevelopExportRequest request, uint maximumWidth, uint maximumHeight,
            byte[] pixels, DevelopRun? run = null, SoftProofSettings? softProof = null, bool clippingOverlay = false) => preview(request, pixels);
        public DevelopExportResult Run(DevelopExportRequest request, DevelopRun? run = null) => throw new NotSupportedException();
        public GrainMendDetectionResult DetectGrainMend(DevelopExportRequest request, DefectRect roi,
            GrainMendDetectionOptions options, DevelopRun? run = null) => throw new NotSupportedException();
    }
}
