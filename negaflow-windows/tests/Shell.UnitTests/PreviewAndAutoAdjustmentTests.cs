using System.Text.Json;
using System.Text.Json.Nodes;
using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Library;
using Negaflow.Shell.Print;
using Negaflow.Shell.Shortcuts;
using static Negaflow.Shell.UnitTests.DevelopTestResults;
using static Negaflow.Shell.UnitTests.TestAssert;
using static Negaflow.Shell.UnitTests.TestFrameFactory;

namespace Negaflow.Shell.UnitTests;

internal static class PreviewAndAutoAdjustmentTests
{
    public static void Run()
    {
        VerifyAutoAdjustCoordinator();
        VerifyPreviewCoordinator();
        VerifyPreviewProxyDimension();
    }

    private static void VerifyPreviewProxyDimension()
    {
        Check(
            DevelopPreviewProxy.InteractiveProxyDimension(0) ==
                DevelopPreviewProxy.InteractiveMaxDimension,
            "proxy_unknown_display_uses_interactive_max");
        Check(
            DevelopPreviewProxy.InteractiveProxyDimension(900) ==
                DevelopPreviewProxy.InteractiveMinDimension,
            "proxy_below_min_clamps_to_1024");
        Check(
            DevelopPreviewProxy.InteractiveProxyDimension(1100) == 1280,
            "proxy_quantizes_up_to_256");
        Check(
            DevelopPreviewProxy.InteractiveProxyDimension(4000) ==
                DevelopPreviewProxy.FullMaxDimension,
            "proxy_above_full_clamps_to_3600");
        Check(
            DevelopPreviewProxy.SettleWindow == TimeSpan.FromMilliseconds(140),
            "proxy_settle_window_is_macos_140ms");
    }

    private static void VerifyAutoAdjustCoordinator()
    {
        LibraryFrameSnapshot corrected = Frame(new ManualBaseRgb(0.2, 0.2, 0.2)) with
        {
            Tone = new ToneAdjustment(1.5, 0.4, 0, 0, 0, 0, 0.2, -0.3, 0.25, 0.1, -0.1),
            ColorModel = new ColorModelRecipe(0.5, -0.2, 0, 0.3, 0, 0, 0, 0),
        };

        LibraryFrameSnapshot neutral = AutoAdjustCoordinator.Neutralise(corrected);
        Check(
            neutral.Tone == ToneAdjustment.Neutral,
            "auto_adjust_measures_a_tone_neutral_frame");
        Check(
            neutral.ColorModel.Warmth == 0.0 && neutral.ColorModel.Tint == 0.0,
            "auto_adjust_measures_a_white_balance_neutral_frame");
        Check(
            neutral.ColorModel.Vibrance == corrected.ColorModel.Vibrance &&
                neutral.Base == corrected.Base,
            "auto_adjust_leaves_the_rest_of_the_recipe_alone");
        LibraryFrameSnapshot toneNeutral = AutoAdjustCoordinator.NeutraliseTone(corrected);
        LibraryFrameSnapshot balanceNeutral = AutoAdjustCoordinator.NeutraliseWhiteBalance(corrected);
        Check(
            toneNeutral.Tone == ToneAdjustment.Neutral &&
                toneNeutral.ColorModel.Warmth == corrected.ColorModel.Warmth &&
                toneNeutral.ColorModel.Vibrance == 0.0 && toneNeutral.ColorModel.Saturation == 0.0,
            "auto_tone_neutralises_only_tone_corrections");
        Check(
            balanceNeutral.Tone == corrected.Tone &&
                balanceNeutral.ColorModel.Warmth == 0.0 && balanceNeutral.ColorModel.Tint == 0.0,
            "auto_white_balance_neutralises_only_white_balance");

        // Assigned, not accumulated: applying the same settings twice lands in the same place.
        AutoAdjustSettings settings = new(
            exposure: 0.5,
            contrast: 0.2,
            highlights: -0.3,
            shadows: 0.4,
            whites: 0.1,
            blacks: -0.05,
            density: 0.15,
            vibrance: 0.25,
            warmth: -0.2,
            tint: 0.1);
        LibraryFrameSnapshot once = AutoAdjustCoordinator.Apply(corrected, settings);
        LibraryFrameSnapshot twice = AutoAdjustCoordinator.Apply(once, settings);
        Check(
            once.Tone == twice.Tone && once.ColorModel == twice.ColorModel,
            "auto_adjust_assigns_rather_than_accumulates");
        Check(
            once.Tone.Exposure == 0.5 && once.Tone.Contrast == 0.2 &&
                once.Tone.Highlight == -0.3 && once.Tone.Shadow == 0.4 &&
                once.ColorModel.Warmth == -0.2 && once.ColorModel.Vibrance == 0.25,
            "auto_adjust_writes_every_value_it_computed");
        Check(
            once.Base == corrected.Base && once.PointCurves == corrected.PointCurves,
            "auto_adjust_does_not_touch_the_film_base_or_other_recipes");
        LibraryFrameSnapshot toneOnly = AutoAdjustCoordinator.ApplyTone(corrected, settings);
        LibraryFrameSnapshot balanceOnly = AutoAdjustCoordinator.ApplyWhiteBalance(corrected, settings);
        Check(
            toneOnly.ColorModel.Warmth == corrected.ColorModel.Warmth &&
                toneOnly.ColorModel.Vibrance == settings.Vibrance &&
                balanceOnly.Tone == corrected.Tone &&
                balanceOnly.ColorModel.Warmth == settings.Warmth,
            "auto_tone_and_white_balance_apply_disjoint_recipe_fields");

        // A frame that cannot be developed must be refused through the dispatcher, not
        // thrown, so the caller handles one shape of answer.
        FakeDispatcher quiet = new(accepts: true);
        FakeExporter neverCalled = new(_ => OkResult());
        AutoAdjustCoordinator refusing = new(neverCalled, quiet);
        AutoAdjustOutcome? refusal = null;
        refusing.RunAsync(
            Frame(null, baseRecipe: new BaseRecipe(BaseEstimationMode.Manual, null, null, null)),
            outcome => refusal = outcome).GetAwaiter().GetResult();
        Check(
            refusal?.Kind == DevelopExportOutcomeKind.Refused,
            "auto_adjust_refuses_an_undevelopable_frame");
        Check(neverCalled.CallCount == 0, "auto_adjust_refusal_skips_the_engine");
    }

    private static void VerifyPreviewCoordinator()
    {
        FakeDispatcher dispatcher = new(accepts: true);
        using ManualResetEventSlim gate = new(initialState: false);
        FakeExporter exporter = new(_ => OkResult(), gate);
        PreviewCoordinator coordinator = new(exporter, dispatcher, 64, 64);

        LibraryFrameSnapshot first = Frame(new ManualBaseRgb(0.2, 0.2, 0.2));
        List<uint> delivered = [];

        Task started = coordinator.RequestAsync(first, outcome => delivered.Add(outcome.Width));
        while (Volatile.Read(ref exporter.CallCount) == 0)
        {
            Thread.Yield();
        }
        Check(coordinator.IsRendering, "preview_reports_rendering");

        // 슬라이더 한 번에 요청이 여러 번 옵니다. 대기 자리는 하나이므로 중간 요청은
        // 합쳐지되, **마지막 것은 반드시 그려져야** 사용자가 방금 한 조작이 화면에 남습니다.
        coordinator.RequestAsync(first, outcome => delivered.Add(outcome.Width));
        coordinator.RequestAsync(first, outcome => delivered.Add(outcome.Width));
        coordinator.RequestAsync(first, outcome => delivered.Add(outcome.Width));

        gate.Set();
        started.GetAwaiter().GetResult();

        Check(exporter.CallCount == 2, "preview_coalesces_to_one_pending");
        // **돌고 있던 인터랙티브 렌더는 취소하지 않습니다.**
        // 앞 판은 새 요청마다 취소했고 취소된 결과는 버려졌습니다. 그래서 슬라이더를
        // 계속 끄는 동안에는 어떤 렌더도 완주하지 못해 **화면이 한 장도 안 바뀌었습니다**
        // — 사용자가 "사진이 바로 반영이 안 된다"고 본 것이 이것입니다. 인터랙티브 한
        // 장은 짧으므로 끝까지 그려서 배달하고, 곧바로 최신 값으로 다음 장을 그립니다.
        Check(exporter.CancelledCount == 0, "preview_lets_the_interactive_render_finish");
        Check(delivered.Count == 2, "preview_delivers_every_finished_interactive_render");
        Check(!coordinator.IsRendering, "preview_clears_rendering_flag");

        // 요청이 겹치지 않으면 그냥 매번 그립니다.
        FakeDispatcher quiet = new(accepts: true);
        FakeExporter sequential = new(_ => OkResult());
        PreviewCoordinator simple = new(sequential, quiet, 64, 64);
        PreviewOutcome? outcomeOne = null;
        simple.RequestAsync(first, outcome => outcomeOne = outcome).GetAwaiter().GetResult();
        Check(outcomeOne?.Kind == DevelopExportOutcomeKind.Completed, "preview_completed");
        Check(outcomeOne?.Width == 100, "preview_reports_width");
        Check(outcomeOne?.Pixels is not null, "preview_hands_back_pixels");

        // 현상할 수 없는 frame 은 엔진을 부르지 않고 이유를 돌려줍니다.
        FakeExporter neverCalled = new(_ => OkResult());
        PreviewCoordinator refusing = new(neverCalled, quiet, 64, 64);
        PreviewOutcome? refusal = null;
        refusing.RequestAsync(Frame(
                null,
                baseRecipe: new BaseRecipe(BaseEstimationMode.Manual, null, null, null)), outcome => refusal = outcome)
            .GetAwaiter().GetResult();
        Check(refusal?.Kind == DevelopExportOutcomeKind.Refused, "preview_refused");
        Check(
            refusal?.Refusal == DevelopRequestRefusal.MissingManualBase,
            "preview_refusal_reason");
        Check(neverCalled.CallCount == 0, "preview_refusal_skips_engine");

        FakeExporter throwing = new(_ => throw new InvalidOperationException("engine gone"));
        PreviewCoordinator faulting = new(throwing, quiet, 64, 64);
        PreviewOutcome? fault = null;
        faulting.RequestAsync(first, outcome => fault = outcome).GetAwaiter().GetResult();
        Check(fault?.Kind == DevelopExportOutcomeKind.Faulted, "preview_faulted");
        Check(!faulting.IsRendering, "preview_clears_flag_after_fault");

        // 엔진이 실패를 돌려도 Completed+빈 화소로 위장하면 캔버스가 ShowEmpty 를 칩니다.
        PreviewOutcome? failedRender = null;
        PreviewCoordinator failed = new(new FakeExporter(_ => FailedResult("decode")), quiet, 64, 64);
        failed.RequestAsync(first, outcome => failedRender = outcome).GetAwaiter().GetResult();
        Check(failedRender?.Kind == DevelopExportOutcomeKind.Faulted, "preview_failed_render_is_faulted");
        Check(failedRender?.Pixels is null, "preview_failed_render_has_no_pixels");

        // 취소가 OperationCanceledException 으로 새어 나와도 마지막 요청은 그려져야 합니다.
        ManualResetEventSlim oceStarted = new(false);
        ManualResetEventSlim oceRelease = new(false);
        int oceCalls = 0;
        FakeExporter oceExporter = new(_ =>
        {
            int call = Interlocked.Increment(ref oceCalls);
            if (call == 1)
            {
                oceStarted.Set();
                oceRelease.Wait();
                throw new OperationCanceledException();
            }
            return OkResult();
        });
        PreviewCoordinator oceCoordinator = new(oceExporter, quiet, 64, 64);
        PreviewOutcome? oceLast = null;
        int oceDelivered = 0;
        Task oceLoop = oceCoordinator.RequestAsync(first, outcome =>
        {
            Interlocked.Increment(ref oceDelivered);
            oceLast = outcome;
        });
        oceStarted.Wait();
        oceCoordinator.RequestAsync(first, outcome =>
        {
            Interlocked.Increment(ref oceDelivered);
            oceLast = outcome;
        });
        oceRelease.Set();
        oceLoop.GetAwaiter().GetResult();
        Check(oceDelivered == 1, "preview_oce_keeps_the_pending_request");
        Check(oceLast?.Kind == DevelopExportOutcomeKind.Completed, "preview_oce_delivers_the_last_request");
        Check(!oceCoordinator.IsRendering, "preview_oce_clears_rendering_flag");

        VerifyPreviewSoftProof(first, quiet);
        VerifyPreviewSettlePass(first);
    }

    private static void VerifyPreviewSettlePass(LibraryFrameSnapshot frame)
    {
        FakeDispatcher dispatcher = new(accepts: true);
        FakeExporter exporter = new(_ => OkResult());
        PreviewCoordinator coordinator = new(exporter, dispatcher, () => 1100);

        coordinator.RequestAsync(frame, _ => { }).GetAwaiter().GetResult();
        Check(exporter.CallCount == 2, "preview_settle_runs_interactive_then_full");
        Check(
            exporter.PreviewMaximumWidths.Count == 2 &&
                exporter.PreviewMaximumWidths[0] == 1280 &&
                exporter.PreviewMaximumWidths[1] == 3600,
            "preview_settle_uses_macos_proxy_then_3600");
    }

    // Soft proof is a view setting, so it belongs to the coordinator rather than to a
    // request. What has to hold is that the engine sees the state that was set when the
    // render began, and that "off" means the engine is told nothing at all.
    private static void VerifyPreviewSoftProof(
        LibraryFrameSnapshot frame,
        FakeDispatcher dispatcher)
    {
        FakeExporter exporter = new(_ => OkResult());
        PreviewCoordinator coordinator = new(exporter, dispatcher, 64, 64);

        coordinator.RequestAsync(frame, _ => { }).GetAwaiter().GetResult();
        Check(exporter.LastSoftProof is null, "preview_without_proof_passes_none");

        SoftProofSettings paper = new(
            true,
            SoftProofSimulation.PaperAndBlackInk,
            new SoftProofRgb(0.877, 0.877, 0.906),
            new SoftProofRgb(0.05, 0.05, 0.05));
        coordinator.SoftProof = paper;
        coordinator.RequestAsync(frame, _ => { }).GetAwaiter().GetResult();
        Check(
            ReferenceEquals(exporter.LastSoftProof, paper),
            "preview_carries_the_configured_proof");

        // Switching proofing off has to reach the engine as "no proof", not as the last
        // proof left in place, or the paper stays on screen after the user turned it off.
        coordinator.SoftProof = null;
        coordinator.RequestAsync(frame, _ => { }).GetAwaiter().GetResult();
        Check(exporter.LastSoftProof is null, "preview_clears_the_proof_when_switched_off");

        // Automatic adjustment measures the develop, not a paper simulation, so it must
        // never carry one even while the screen is proofed.
        FakeExporter autoExporter = new(_ => OkResult());
        AutoAdjustCoordinator auto = new(autoExporter, dispatcher);
        auto.RunAsync(frame, _ => { }).GetAwaiter().GetResult();
        Check(
            autoExporter.LastSoftProof is null,
            "auto_adjust_measures_an_unproofed_render");
    }

    private static bool Near(double actual, double expected) => Math.Abs(actual - expected) <= 1e-9;

    private static bool NearRect(CropDisplayRect actual, double x, double y, double width, double height) =>
        Near(actual.X, x) && Near(actual.Y, y) && Near(actual.Width, width) && Near(actual.Height, height);

    /// <summary>
    /// 배치 계획입니다. 같은 이름이 두 번 나오지 않아야 하고, 순번은 고른 순서를 따라야 하며,
    /// 이미 있는 파일을 덮지 않아야 합니다 — 내보내기가 이전 결과를 지우면 되돌릴 수 없습니다.
    /// </summary>
}
