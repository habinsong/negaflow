using System.Collections.Concurrent;
using Negaflow.Catalog;
using Negaflow.Interop;
using static Negaflow.Shell.UnitTests.TestAssert;
using static Negaflow.Shell.UnitTests.TestFrameFactory;

namespace Negaflow.Shell.UnitTests;

internal static class InfraredCleanCoordinatorTests
{
    public static void Run()
    {
        VerifySelectionMustRemainCurrentAfterDelay();
        VerifyPhotoSwitchDoesNotCancelRunningDetection();
        VerifyManualToolCancelsRunningDetection();
    }

    private static void VerifySelectionMustRemainCurrentAfterDelay()
    {
        LibraryFrameSnapshot frame = Frame(null);
        string? activeFrameId = frame.Id;
        int prepared = 0;
        int detected = 0;
        var delay = new TaskCompletionSource(
            TaskCreationOptions.RunContinuationsAsynchronously);
        var dispatcher = new QueuedUiDispatcher();
        using var coordinator = new LibraryInfraredCleanCoordinator(
            dispatcher,
            () => activeFrameId,
            _ =>
            {
                prepared++;
                return Work(frame);
            },
            (_, _) =>
            {
                detected++;
                return new InfraredDefectDetectionOutcome(null, true);
            },
            (_, _) => { },
            _ => { },
            _ => delay.Task);

        coordinator.Schedule(frame.Id);
        Check(prepared == 0 && detected == 0,
            "ir_selection_schedule_returns_before_detection");
        activeFrameId = Guid.NewGuid().ToString("D");
        delay.SetResult();
        Check(SpinWait.SpinUntil(() => dispatcher.Count == 1, 2000),
            "ir_selection_delay_queues_ui_guard");
        dispatcher.Drain();
        Check(prepared == 0 && detected == 0,
            "ir_selection_changed_during_delay_skips_detection");
    }

    private static void VerifyPhotoSwitchDoesNotCancelRunningDetection()
    {
        LibraryFrameSnapshot frame = Frame(null);
        string? activeFrameId = frame.Id;
        var dispatcher = new QueuedUiDispatcher();
        using var started = new ManualResetEventSlim();
        using var release = new ManualResetEventSlim();
        bool cancellationObserved = true;
        int completed = 0;
        using var coordinator = new LibraryInfraredCleanCoordinator(
            dispatcher,
            () => activeFrameId,
            _ => Work(frame),
            (_, run) =>
            {
                started.Set();
                release.Wait();
                cancellationObserved = run.IsCancelRequested;
                return new InfraredDefectDetectionOutcome(null, true);
            },
            (_, _) => completed++,
            _ => { },
            _ => Task.CompletedTask);

        coordinator.Schedule(frame.Id);
        Check(SpinWait.SpinUntil(() => dispatcher.Count == 1, 2000),
            "ir_running_photo_switch_queues_start");
        dispatcher.Drain();
        Check(started.Wait(2000), "ir_running_photo_switch_starts_worker");
        activeFrameId = Guid.NewGuid().ToString("D");
        release.Set();
        Check(SpinWait.SpinUntil(() => dispatcher.Count == 1, 2000),
            "ir_running_photo_switch_queues_completion");
        dispatcher.Drain();
        Check(!cancellationObserved && completed == 1,
            "ir_running_photo_switch_keeps_mac_completion_contract");
    }

    private static void VerifyManualToolCancelsRunningDetection()
    {
        LibraryFrameSnapshot frame = Frame(null);
        var dispatcher = new QueuedUiDispatcher();
        using var started = new ManualResetEventSlim();
        using var release = new ManualResetEventSlim();
        int callerThreadId = Environment.CurrentManagedThreadId;
        int detectorThreadId = 0;
        bool cancellationObserved = false;
        int rearmed = 0;
        int completed = 0;
        using var coordinator = new LibraryInfraredCleanCoordinator(
            dispatcher,
            () => frame.Id,
            _ => Work(frame),
            (_, run) =>
            {
                detectorThreadId = Environment.CurrentManagedThreadId;
                started.Set();
                release.Wait();
                cancellationObserved = run.IsCancelRequested;
                return new InfraredDefectDetectionOutcome(null, true);
            },
            (_, _) => completed++,
            _ => rearmed++,
            _ => Task.CompletedTask);

        coordinator.Schedule(frame.Id);
        Check(SpinWait.SpinUntil(() => dispatcher.Count == 1, 2000),
            "ir_manual_priority_queues_start");
        dispatcher.Drain();
        Check(started.Wait(2000), "ir_manual_priority_starts_worker");
        Check(coordinator.YieldToManualTool(frame.Id),
            "ir_manual_priority_cancels_running_session");
        release.Set();
        Check(SpinWait.SpinUntil(() => dispatcher.Count == 1, 2000),
            "ir_manual_priority_queues_cancelled_completion");
        dispatcher.Drain();
        Check(detectorThreadId != callerThreadId && cancellationObserved &&
              rearmed == 1 && completed == 0,
            "ir_manual_priority_rearms_and_discards_cancelled_result");
    }

    private static LibraryInfraredCleanWork Work(LibraryFrameSnapshot frame) => new(
        frame.Id,
        Guid.Parse("4fa76528-8ea7-49ef-af2a-cb1d24786216"),
        new DefectSourceIdentity(4, new string('a', 64)),
        frame.SourcePath,
        frame.SourcePath + ".ir.tiff",
        frame.SourceKind,
        frame.DefectRecipeRevision);

    private sealed class QueuedUiDispatcher : IUiDispatcher
    {
        private readonly ConcurrentQueue<Action> callbacks = new();

        public bool HasThreadAccess => true;

        public int Count => callbacks.Count;

        public bool TryEnqueue(Action callback)
        {
            callbacks.Enqueue(callback);
            return true;
        }

        public void Drain()
        {
            while (callbacks.TryDequeue(out Action? callback))
            {
                callback();
            }
        }
    }
}
