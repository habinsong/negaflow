using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
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
        VerifyClosedLoop().GetAwaiter().GetResult();
        VerifyNeutralPickUserValues();
    }

    // 중립 스포이드(macOS `AppModel.userWhiteBalance`): 네이티브가 푼 값은 룩 프리셋 몫까지 더한
    // 합입니다. 저장할 사용자 값은 프리셋 몫을 빼고 슬라이더 범위(±4)로 자릅니다.
    private static void VerifyNeutralPickUserValues()
    {
        try
        {
            LookPresetLibrary.SetForTests([new LookPreset(
                "warm-look", "Warm", 1, [FilmType.ColorNegative],
                new LookPresetTone(0, 0, 0, 0, 0, null),
                new LookPresetColor(0.5, -0.25, 0, 0),
                new LookPresetTexture(0, 0, 0))]);
            (double warmth, double tint) = DevelopToneEditor.UserWhiteBalance("warm-look", -1.0, 0.75);
            Check(Math.Abs(warmth - -1.5) < 1e-12 && Math.Abs(tint - 1.0) < 1e-12,
                "neutral_pick_subtracts_the_look_preset_share");
            (double plainWarmth, double plainTint) = DevelopToneEditor.UserWhiteBalance(null, -1.0, 0.75);
            Check(plainWarmth == -1.0 && plainTint == 0.75, "neutral_pick_without_preset_assigns_the_solution");
            (double clampedWarmth, _) = DevelopToneEditor.UserWhiteBalance("warm-look", -3.8, 0.0);
            Check(clampedWarmth == -ColorModelRecipe.MaximumWhiteBalance, "neutral_pick_clamps_to_the_slider_range");
        }
        finally
        {
            LookPresetLibrary.SetForTests([]);
        }
        Check(DevelopBaseReadout.FormatValues("Warmth %.2f · Tint %.2f", -1.234, 0.5) ==
            $"Warmth {(-1.234).ToString("0.00", System.Globalization.CultureInfo.CurrentCulture)} · Tint {0.5.ToString("0.00", System.Globalization.CultureInfo.CurrentCulture)}",
            "neutral_pick_status_fills_both_values");
    }

    // 자동 톤 폐루프(macOS `AppModel.autoTone`): 중립 렌더로 첫 값을 계산하고, 그 값을 frame 의
    // 나머지 설정과 함께 다시 그려 한 번 바로잡습니다. 자동 WB 는 한 번만 그립니다.
    private static async Task VerifyClosedLoop()
    {
        var requests = new List<DevelopExportRequest>();
        bool failVerification = false;
        var exporter = new PixelExporter((request, pixels) =>
        {
            int index;
            lock (requests) { requests.Add(request); index = requests.Count; }
            pixels[0] = (byte)index;   // 몇 번째 렌더인지 화소로 넘깁니다.
            return failVerification && index == 2 ? FailedResult("verify_failed") : OkResult();
        });
        bool? sawMonochrome = null;
        var first = new AutoAdjustSettings(0.5, 0.1, -0.2, 0.1, 0.1, -0.05, 0.0, 0.2, -0.3, 0.1);
        var coordinator = new AutoAdjustCoordinator(exporter, new FakeDispatcher(true), 128,
            (pixels, _, _, monochrome) => { sawMonochrome = monochrome; return first; },
            (pixels, _, _, _, given) => new AutoAdjustSettings(given.Exposure + (pixels[0] / 10.0), given.Contrast,
                given.Highlights, given.Shadows, given.Whites + 0.05, given.Blacks, given.Density, given.Vibrance,
                given.Warmth, given.Tint));
        LibraryFrameSnapshot frame = Frame(new ManualBaseRgb(0.7, 0.3, 0.2)) with
        {
            SourcePath = Path.Combine(Path.GetTempPath(), "auto-loop.tif"),
            Tone = new ToneAdjustment(1.0, 0.3, 0.6, 0, 0, 0),
            ColorModel = ColorModelRecipe.Identity with { Saturation = 0.3, ColorDepth = 0.2 },
        };
        var outcomes = new List<AutoAdjustOutcome>();
        await coordinator.RunToneAsync(frame, outcomes.Add);
        Check(requests.Count == 2, "auto_tone_renders_neutral_then_verifies");
        Check(requests[0].ExposureStops == 0F && requests[0].Highlights == 0F && requests[0].Saturation == 0F,
            "auto_tone_first_render_is_tone_neutral");
        Check(requests[1].ExposureStops == 0.5F && requests[1].Highlights == 0.6F &&
            requests[1].Saturation == 0.3F && requests[1].ColorDepth == 0.2F,
            "auto_tone_verifies_with_the_frames_other_settings");
        LibraryFrameSnapshot tone = outcomes[0].Frame!;
        Check(Math.Abs(tone.Tone.Exposure - 0.7) < 1e-12 && Math.Abs(tone.Tone.Whites - 0.15) < 1e-12 &&
            tone.Tone.Contrast == 0.1 && tone.Tone.CurveHighlights == 0.6,
            "auto_tone_applies_the_refined_values");
        Check(tone.ColorModel.Saturation == 0.3 && tone.ColorModel.Vibrance == 0.2,
            "auto_tone_keeps_user_saturation");
        Check(sawMonochrome == false, "auto_tone_uses_the_colour_shoulder_for_colour_film");

        requests.Clear();
        outcomes.Clear();
        await coordinator.RunWhiteBalanceAsync(frame, outcomes.Add);
        Check(requests.Count == 1 && outcomes[0].Frame!.ColorModel.Warmth == -0.3 &&
            outcomes[0].Frame!.Tone == frame.Tone, "auto_white_balance_renders_once_without_refinement");

        requests.Clear();
        outcomes.Clear();
        await coordinator.RunToneAsync(Frame(new ManualBaseRgb(0.5, 0.5, 0.5), filmType: FilmType.BlackAndWhiteNegative) with
            { SourcePath = Path.Combine(Path.GetTempPath(), "auto-loop-bw.tif") }, outcomes.Add);
        Check(sawMonochrome == true, "auto_tone_uses_the_monochrome_shoulder_for_bw_negatives");

        // 검증 렌더가 실패하면 첫 값을 그대로 씁니다 — 첫 값도 유효한 답입니다.
        requests.Clear();
        outcomes.Clear();
        failVerification = true;
        await coordinator.RunToneAsync(frame, outcomes.Add);
        Check(requests.Count == 2 && outcomes is [{ Kind: DevelopExportOutcomeKind.Completed }] &&
            outcomes[0].Frame!.Tone.Exposure == 0.5 && !coordinator.IsRunning,
            "auto_tone_falls_back_to_the_first_answer_when_verification_fails");
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
        // 톤 뒤에 화이트밸런스를 눌러도 톤이 씹히지 않습니다 — 같은 종류의 새 요청만 앞 것을 대체하고,
        // 화이트밸런스는 톤의 완료 처리가 돈 뒤에 시작합니다.
        var bothTone = coordinator.RunToneAsync(source, outcomes.Add);
        var bothBalance = coordinator.RunWhiteBalanceAsync(source, outcomes.Add);
        await bothTone;
        dispatcher.Drain();
        await bothBalance;
        dispatcher.Drain();
        Check(outcomes.Count == 2 && !coordinator.IsRunning, "auto_tone_and_white_balance_both_deliver");
        // 화이트밸런스는 앞서 누른 톤이 반영된 프레임을 읽습니다.
        outcomes.Clear();
        var current = source;
        var toneRun = coordinator.RunToneAsync(() => current, outcome => { outcomes.Add(outcome); current = outcome.Frame!; });
        var balanceRun = coordinator.RunWhiteBalanceAsync(() => current, outcomes.Add);
        await toneRun;
        dispatcher.Drain();
        await balanceRun;
        dispatcher.Drain();
        Check(outcomes.Count == 2 && outcomes[1].Frame!.Tone == outcomes[0].Frame!.Tone,
            "auto_white_balance_measures_after_the_earlier_tone_result");
        outcomes.Clear();
        await coordinator.RunToneAsync(source, outcomes.Add);
        await coordinator.RunToneAsync(source, outcomes.Add);
        dispatcher.Drain();
        Check(outcomes.Count == 1 && !coordinator.IsRunning, "auto_new_tone_request_suppresses_previous_queued_tone");
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
