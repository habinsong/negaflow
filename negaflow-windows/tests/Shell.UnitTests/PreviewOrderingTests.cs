using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using static Negaflow.Shell.UnitTests.DevelopTestResults;
using static Negaflow.Shell.UnitTests.TestAssert;
using static Negaflow.Shell.UnitTests.TestFrameFactory;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// 슬라이더를 <b>올렸다 내리는</b> 동안 화면에 남는 그림이 마지막 값과 같은지 봅니다.
/// </summary>
/// <remarks>
/// <para>
/// 실제로 났던 고장: 노출을 올리다가 내리면 <b>올라가는 것만 반영되고 내려가는 것은 화면에
/// 안 남았습니다.</b> 원인은 두 가지가 겹친 것입니다.
/// </para>
/// <list type="number">
/// <item>배달이 <c>dispatcher.TryEnqueue</c> 로 UI 큐에 실리므로 두 장이 연달아 실릴 수
/// 있고, 나중에 처리되는 쪽이 <b>더 옛 편집 상태</b>일 수 있었습니다.</item>
/// <item>화소 버퍼가 두 장뿐이라, 배달이 큐에 남아 있는 사이 그 다음다음 렌더가 같은 버퍼를
/// <b>덮어썼습니다.</b> 그러면 배달의 리비전과 실제 화소가 어긋납니다.</item>
/// </list>
/// <para>
/// 그래서 리비전 각인(오래된 배달은 화면이 버림)과 버퍼 임대(배달된 버퍼는 UI 가 다 쓸
/// 때까지 재사용 금지)를 <b>둘 다</b> 겁니다. 이 시험은 그 둘이 같이 있어야만 통과합니다.
/// </para>
/// </remarks>
internal static class PreviewOrderingTests
{
    public static void Run()
    {
        VerifyLastEditWinsAcrossAQueuedDispatcher();
        VerifySwitchingFramesCancelsThePreviousInteractive();
        VerifyTerminationCancelsAndDrainsPreview();
        VerifyLastQueuedEditWinsWhileFirstIsHeld();
        VerifyLastQueuedFrameWinsWhileFirstIsHeld();
    }

    private static void VerifyTerminationCancelsAndDrainsPreview()
    {
        ManualResetEventSlim gate = new(false);
        FakeExporter exporter = new(_ => OkResult(), gate);
        PreviewCoordinator coordinator = new(
            exporter,
            new FakeDispatcher(accepts: true),
            64,
            64);
        Task started = coordinator.RequestAsync(FrameWithExposure(0.1), _ => { });
        SpinWait.SpinUntil(() => Volatile.Read(ref exporter.CallCount) == 1, 5000);
        _ = coordinator.RequestAsync(FrameWithExposure(0.2), _ => { });

        Task drained = coordinator.CancelAndDrainAsync();
        bool completed = drained.Wait(TimeSpan.FromSeconds(5));
        started.GetAwaiter().GetResult();
        Check(completed &&
              exporter.CancelledCount == 1 &&
              exporter.CallCount == 1 &&
              !coordinator.IsRendering,
            "preview_termination_cancels_active_and_discards_pending");
    }

    /// <summary>배달을 모아 두었다가 한꺼번에 흘리는 dispatcher — 실제 UI 큐와 같은 순서입니다.</summary>
    private sealed class QueuedDispatcher : IUiDispatcher
    {
        private readonly List<Action> queue = [];

        public bool HasThreadAccess => false;

        public bool TryEnqueue(Action callback)
        {
            lock (queue)
            {
                queue.Add(callback);
            }
            return true;
        }

        public int PendingCount
        {
            get
            {
                lock (queue)
                {
                    return queue.Count;
                }
            }
        }

        public bool DrainOne()
        {
            Action next;
            lock (queue)
            {
                if (queue.Count == 0)
                {
                    return false;
                }
                next = queue[0];
                queue.RemoveAt(0);
            }
            next();
            return true;
        }

        public void Drain()
        {
            while (DrainOne())
            {
            }
        }
    }

    /// <summary>요청의 노출값을 화소 첫 바이트에 찍는 엔진입니다. 무엇이 그려졌는지 봅니다.</summary>
    private sealed class StampingExporter : IDevelopExporter
    {
        public DevelopExportResult Preview(
            DevelopExportRequest request,
            uint maximumWidth,
            uint maximumHeight,
            byte[] pixels,
            DevelopRun? run = null,
            SoftProofSettings? softProof = null,
            bool clippingOverlay = false)
        {
            _ = maximumWidth;
            _ = maximumHeight;
            _ = softProof;
            _ = clippingOverlay;
            if (run is { IsCancelRequested: true })
            {
                return CancelledResult();
            }
            // 노출은 0…5 stops 를 쓰므로 20배로 찍으면 0.05 눈금까지 구분됩니다.
            pixels[0] = (byte)Math.Clamp(Math.Round(request.ExposureStops * 20.0), 0, 255);
            return OkResult();
        }

        public DevelopExportResult Run(DevelopExportRequest request, DevelopRun? run = null) => OkResult();

        public GrainMendDetectionResult DetectGrainMend(
            DevelopExportRequest request,
            DefectRect rawRoi,
            GrainMendDetectionOptions options,
            DevelopRun? run = null) =>
            new(FailedResult("detector_unavailable"), 0U, 0U, 0UL, 0UL);
    }

    /// <summary>첫 프리뷰를 붙잡아 사진 전환이 그걸 끊는지 봅니다.</summary>
    private sealed class HoldFirstExporter : IDevelopExporter
    {
        public readonly ManualResetEventSlim FirstEntered = new(false);
        public readonly ManualResetEventSlim ReleaseFirst = new(false);
        public int Starts;

        public DevelopExportResult Preview(
            DevelopExportRequest request,
            uint maximumWidth,
            uint maximumHeight,
            byte[] pixels,
            DevelopRun? run = null,
            SoftProofSettings? softProof = null,
            bool clippingOverlay = false)
        {
            _ = maximumWidth;
            _ = maximumHeight;
            _ = softProof;
            _ = clippingOverlay;
            int start = Interlocked.Increment(ref Starts);
            if (start == 1)
            {
                FirstEntered.Set();
                if (!ReleaseFirst.Wait(TimeSpan.FromSeconds(5)))
                {
                    return CancelledResult();
                }
            }
            if (run is { IsCancelRequested: true })
            {
                return CancelledResult();
            }
            pixels[0] = (byte)Math.Clamp(Math.Round(request.ExposureStops * 20.0), 0, 255);
            return OkResult();
        }

        public DevelopExportResult Run(DevelopExportRequest request, DevelopRun? run = null) => OkResult();

        public GrainMendDetectionResult DetectGrainMend(
            DevelopExportRequest request,
            DefectRect rawRoi,
            GrainMendDetectionOptions options,
            DevelopRun? run = null) =>
            new(FailedResult("detector_unavailable"), 0U, 0U, 0UL, 0UL);
    }

    private static LibraryFrameSnapshot FrameWithExposure(double stops)
    {
        LibraryFrameSnapshot frame = Frame(new ManualBaseRgb(0.2, 0.2, 0.2));
        return frame with { Tone = frame.Tone with { Exposure = stops } };
    }

    private static void VerifyLastEditWinsAcrossAQueuedDispatcher()
    {
        QueuedDispatcher dispatcher = new();
        StampingExporter exporter = new();
        PreviewCoordinator coordinator = new(exporter, dispatcher, 64, 64);

        // 화면 역할입니다 — 코디네이터가 준 리비전으로 오래된 배달을 버립니다.
        int presentedRevision = 0;
        byte presented = 0;
        void Show(PreviewOutcome outcome)
        {
            if (outcome.Kind != DevelopExportOutcomeKind.Completed ||
                outcome.Pixels is not { } pixels)
            {
                return;
            }
            if (outcome.Revision < presentedRevision)
            {
                return;
            }
            presentedRevision = outcome.Revision;
            presented = pixels[0];
        }

        // 올렸다가 내립니다. 마지막 값은 0.30 입니다.
        //
        // **한 번에 하나씩** 요청합니다. 한꺼번에 넣으면 코디네이터가 대기 자리에서
        // 합쳐 버려 렌더가 두 번밖에 안 돌고, 그러면 이 시험은 아무것도 재현하지 못합니다.
        // 실제 드래그는 한 장이 끝난 뒤 다음 값이 들어오므로 렌더가 값마다 한 번씩 돕니다.
        // 배달은 그동안 **큐에 쌓입니다** — 그것이 재현하려는 상태입니다.
        double[] drag = [0.10, 0.25, 0.40, 0.55, 0.70, 0.55, 0.40, 0.30];
        // 배달마다 (리비전, 화소)를 그대로 적어 둡니다. 임대가 없으면 다음다음 렌더가 같은
        // 버퍼를 덮어써 이 짝이 어긋납니다.
        List<(int Revision, byte Pixel)> deliveries = [];
        void Record(PreviewOutcome outcome)
        {
            if (outcome.Kind == DevelopExportOutcomeKind.Completed &&
                outcome.Pixels is { } pixels)
            {
                deliveries.Add((outcome.Revision, pixels[0]));
            }
            Show(outcome);
        }

        foreach (double stops in drag)
        {
            Task started = coordinator.RequestAsync(FrameWithExposure(stops), Record);
            // 렌더가 끝날 때까지 기다립니다. 임대가 막히면 큐를 흘려 풀어 줍니다 —
            // 실제 UI 스레드가 하는 일과 같습니다. 단, **한 장은 큐에 남겨 둡니다.**
            for (int spin = 0; spin < 2000 && !started.IsCompleted; ++spin)
            {
                if (dispatcher.PendingCount > 1)
                {
                    dispatcher.DrainOne();
                }
                Thread.Sleep(1);
            }
            started.GetAwaiter().GetResult();
        }
        dispatcher.Drain();

        Check(deliveries.Count == drag.Length, "preview_delivers_every_render_once");
        // 배달된 화소가 그 배달의 리비전과 짝이 맞아야 합니다. 리비전은 요청 순서이므로
        // 첫 배달이 drag[0], 두 번째가 drag[1] … 입니다.
        bool paired = true;
        for (int index = 0; index < deliveries.Count && index < drag.Length; ++index)
        {
            if (deliveries[index].Pixel != (byte)Math.Round(drag[index] * 20.0))
            {
                paired = false;
            }
        }
        Check(paired, "preview_delivered_pixels_match_their_own_revision");

        byte expected = (byte)Math.Round(drag[^1] * 20.0);
        Check(
            presented == expected,
            $"preview_last_edit_wins_after_drag_up_then_down (expected {expected}, presented {presented})");
        Check(
            presentedRevision > 0,
            "preview_outcomes_carry_a_revision");
    }

    private static void VerifySwitchingFramesCancelsThePreviousInteractive()
    {
        QueuedDispatcher dispatcher = new();
        HoldFirstExporter exporter = new();
        PreviewCoordinator coordinator = new(exporter, dispatcher, 64, 64)
        {
            // 정착 패스가 끼면 첫 렌더가 두 번 들어가 시험이 흔들립니다.
        };

        byte presented = 0;
        string? presentedFrame = null;
        void Show(PreviewOutcome outcome)
        {
            if (outcome.Kind != DevelopExportOutcomeKind.Completed ||
                outcome.Pixels is not { } pixels)
            {
                return;
            }
            presented = pixels[0];
            presentedFrame = outcome.FrameId;
        }

        LibraryFrameSnapshot first = FrameWithExposure(0.05) with { Id = "frame-a" };
        LibraryFrameSnapshot second = FrameWithExposure(0.10) with { Id = "frame-b" };
        Task started = coordinator.RequestAsync(first, Show);
        Check(exporter.FirstEntered.Wait(TimeSpan.FromSeconds(5)), "preview_first_frame_entered_engine");
        _ = coordinator.RequestAsync(second, Show);
        exporter.ReleaseFirst.Set();
        for (int spin = 0; spin < 2000 && !started.IsCompleted; ++spin)
        {
            dispatcher.DrainOne();
            Thread.Sleep(1);
        }
        started.GetAwaiter().GetResult();
        for (int spin = 0; spin < 2000 && coordinator.IsRendering; ++spin)
        {
            dispatcher.DrainOne();
            Thread.Sleep(1);
        }
        dispatcher.Drain();

        Check(
            presented == 2 && presentedFrame == "frame-b",
            $"preview_switch_cancels_previous_frame (presented={presented}, frame={presentedFrame})");
    }

    private static void VerifyLastQueuedEditWinsWhileFirstIsHeld()
    {
        QueuedDispatcher dispatcher = new();
        HoldFirstExporter exporter = new();
        PreviewCoordinator coordinator = new(exporter, dispatcher, 64, 64);
        byte presented = 0;
        void Show(PreviewOutcome outcome)
        {
            if (outcome.Kind == DevelopExportOutcomeKind.Completed &&
                outcome.Pixels is { } pixels)
            {
                presented = pixels[0];
            }
        }

        Task first = coordinator.RequestAsync(FrameWithExposure(0.05), Show);
        Check(exporter.FirstEntered.Wait(TimeSpan.FromSeconds(5)), "burst_first_entered");
        foreach (double stops in new[] { 0.20, 0.40, 0.70, 0.15 })
        {
            _ = coordinator.RequestAsync(FrameWithExposure(stops), Show);
        }
        exporter.ReleaseFirst.Set();
        first.GetAwaiter().GetResult();
        for (int spin = 0; spin < 4000 && coordinator.IsRendering; ++spin)
        {
            dispatcher.DrainOne();
            Thread.Sleep(1);
        }
        dispatcher.Drain();
        Check(
            presented == (byte)Math.Round(0.15 * 20.0),
            $"preview_last_queued_edit_wins (presented={presented})");
    }

    private static void VerifyLastQueuedFrameWinsWhileFirstIsHeld()
    {
        QueuedDispatcher dispatcher = new();
        HoldFirstExporter exporter = new();
        PreviewCoordinator coordinator = new(exporter, dispatcher, 64, 64);
        string? presentedFrame = null;
        void Show(PreviewOutcome outcome)
        {
            if (outcome.Kind == DevelopExportOutcomeKind.Completed)
            {
                presentedFrame = outcome.FrameId;
            }
        }

        LibraryFrameSnapshot firstFrame = FrameWithExposure(0.05) with { Id = "frame-a" };
        Task first = coordinator.RequestAsync(firstFrame, Show);
        Check(exporter.FirstEntered.Wait(TimeSpan.FromSeconds(5)), "burst_frame_first_entered");
        _ = coordinator.RequestAsync(FrameWithExposure(0.10) with { Id = "frame-b" }, Show);
        _ = coordinator.RequestAsync(FrameWithExposure(0.20) with { Id = "frame-c" }, Show);
        _ = coordinator.RequestAsync(FrameWithExposure(0.30) with { Id = "frame-d" }, Show);
        exporter.ReleaseFirst.Set();
        first.GetAwaiter().GetResult();
        for (int spin = 0; spin < 4000 && coordinator.IsRendering; ++spin)
        {
            dispatcher.DrainOne();
            Thread.Sleep(1);
        }
        dispatcher.Drain();
        Check(
            presentedFrame == "frame-d",
            $"preview_last_queued_frame_wins (presented={presentedFrame})");
    }
}
