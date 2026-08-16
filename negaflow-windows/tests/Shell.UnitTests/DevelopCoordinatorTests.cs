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

internal static class DevelopCoordinatorTests
{
    public static void Run()
    {
        VerifyDevelopExportCoordinator();
    }

    private static void VerifyDevelopExportCoordinator()
    {
        const string destination = @"C:\exports\IMG_0001.png";
        LibraryFrameSnapshot developable = Frame(new ManualBaseRgb(0.2, 0.2, 0.2));
        int callerThreadId = Environment.CurrentManagedThreadId;

        FakeDispatcher dispatcher = new(accepts: true);
        FakeExporter exporter = new(_ => OkResult());
        DevelopExportCoordinator coordinator = new(exporter, dispatcher);

        DevelopExportOutcome? observed = null;
        bool delivered = coordinator
            .StartAsync(developable, destination, DevelopExportFormat.Png16,
                outcome => observed = outcome)
            .GetAwaiter().GetResult();

        Check(delivered, "coordinator_delivers_result");
        Check(observed?.Kind == DevelopExportOutcomeKind.Completed, "coordinator_completed");
        Check(observed?.Result?.Succeeded == true, "coordinator_result_succeeded");
        Check(observed?.Result?.ImageWidth == 100, "coordinator_result_carried");
        Check(exporter.CallCount == 1, "coordinator_calls_exporter_once");
        // 네이티브 호출이 호출 스레드에서 돌면 UI 가 현상 내내 굳습니다.
        Check(exporter.LastThreadId != callerThreadId, "coordinator_runs_off_calling_thread");
        Check(!coordinator.IsRunning, "coordinator_clears_running_flag");

        // 거부도 같은 길로 돌아옵니다. 성공만 dispatcher 를 타면 실패 경로가 백그라운드에서
        // 컨트롤을 건드리게 됩니다.
        FakeExporter neverCalled = new(_ => OkResult());
        DevelopExportCoordinator refusing = new(neverCalled, dispatcher);
        DevelopExportOutcome? refusal = null;
        Check(
            refusing.StartAsync(Frame(
                null,
                baseRecipe: new BaseRecipe(BaseEstimationMode.Manual, null, null, null)), destination, DevelopExportFormat.Png16,
                outcome => refusal = outcome).GetAwaiter().GetResult(),
            "coordinator_delivers_refusal");
        Check(refusal?.Kind == DevelopExportOutcomeKind.Refused, "coordinator_refused_kind");
        Check(
            refusal?.Refusal == DevelopRequestRefusal.MissingManualBase,
            "coordinator_refusal_reason");
        Check(neverCalled.CallCount == 0, "coordinator_refusal_skips_native");

        // 네이티브가 던진 예외를 관측하지 않으면 UI 는 영원히 기다립니다.
        FakeExporter throwing = new(_ => throw new InvalidOperationException("engine gone"));
        DevelopExportCoordinator faulting = new(throwing, dispatcher);
        DevelopExportOutcome? fault = null;
        Check(
            faulting.StartAsync(developable, destination, DevelopExportFormat.Png16,
                outcome => fault = outcome).GetAwaiter().GetResult(),
            "coordinator_delivers_fault");
        Check(fault?.Kind == DevelopExportOutcomeKind.Faulted, "coordinator_faulted_kind");
        Check(fault?.FaultMessage == "engine gone", "coordinator_fault_message");
        Check(!faulting.IsRunning, "coordinator_clears_flag_after_fault");

        VerifyCoordinatorBusyPath(developable, destination);
        VerifyCoordinatorDroppedResult(developable, destination);
    }

    private static void VerifyCoordinatorBusyPath(
        LibraryFrameSnapshot frame,
        string destination)
    {
        using ManualResetEventSlim gate = new(initialState: false);
        FakeDispatcher dispatcher = new(accepts: true);
        FakeExporter exporter = new(_ => OkResult(), gate);
        DevelopExportCoordinator coordinator = new(exporter, dispatcher);

        Task<bool> first = coordinator.StartAsync(
            frame, destination, DevelopExportFormat.Png16, _ => { });
        while (Volatile.Read(ref exporter.CallCount) == 0)
        {
            Thread.Yield();
        }

        DevelopExportOutcome? second = null;
        bool delivered = coordinator
            .StartAsync(frame, destination, DevelopExportFormat.Png16,
                outcome => second = outcome)
            .GetAwaiter().GetResult();

        Check(delivered, "coordinator_delivers_busy");
        Check(second?.Kind == DevelopExportOutcomeKind.Busy, "coordinator_busy_kind");
        Check(coordinator.IsRunning, "coordinator_reports_running");

        gate.Set();
        Check(first.GetAwaiter().GetResult(), "coordinator_first_still_delivers");
        Check(exporter.CallCount == 1, "coordinator_busy_did_not_run_twice");
        Check(!coordinator.IsRunning, "coordinator_running_clears_after_first");
    }

    private static void VerifyCoordinatorDroppedResult(
        LibraryFrameSnapshot frame,
        string destination)
    {
        // 창이 닫혀 큐가 종료된 뒤입니다. TryEnqueue 가 false 를 돌려주고 콜백은 영영 실행되지
        // 않습니다. 그래도 진행 중 표시는 풀려야 하며, 아니면 앱이 영영 "현상 중" 으로 남습니다.
        FakeDispatcher closed = new(accepts: false);
        FakeExporter exporter = new(_ => OkResult());
        DevelopExportCoordinator coordinator = new(exporter, closed);

        bool callbackRan = false;
        // UI 스레드가 아닌 곳에서 시작해야 TryEnqueue 경로를 지납니다.
        bool delivered = Task.Run(() => coordinator.StartAsync(
                frame, destination, DevelopExportFormat.Png16,
                _ => callbackRan = true))
            .GetAwaiter().GetResult();

        Check(!delivered, "coordinator_reports_dropped_result");
        Check(!callbackRan, "coordinator_dropped_callback_did_not_run");
        Check(closed.EnqueueCount == 1, "coordinator_attempted_enqueue_once");
        Check(!coordinator.IsRunning, "coordinator_clears_flag_when_dropped");
        Check(exporter.CallCount == 1, "coordinator_dropped_still_ran_native");
    }

    /// <summary>
    /// 씨앗으로 만든 카탈로그를 셸과 같은 방식으로 열어, 사진이 왜 안 보이는지 UI 없이 봅니다.
    /// </summary>
}
