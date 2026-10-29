using System.Runtime.InteropServices;

namespace Negaflow.Interop.ContractTests;

internal static unsafe class RunStateContractTests
{
    internal static void VerifyManaged(ContractTestContext context)
    {
        // Native 호출 없이 UI 취소/진행 조회와 워커 Dispose를 같은 객체에서 경합시킵니다.
        Parallel.For(0, 2_000, iteration =>
        {
            using var cancellation = new CancellationTokenSource();
            using var run = new DevelopRun(cancellation.Token);
            Parallel.Invoke(
                () => { for (int i = 0; i < 32; i++) { run.Cancel(); _ = run.ProgressPermille; _ = run.Stage; _ = run.IsCancelRequested; } },
                () => { cancellation.Cancel(); run.Dispose(); },
                run.Dispose);
            if (run.IsCancelRequested || run.Stage != DevelopExportStage.None || run.ProgressPermille != 0)
            { throw new InvalidOperationException("Disposed run state remained accessible."); }
        });
        context.Check(true, "run_state_cancel_reads_and_dispose_race_without_corruption_or_deadlock");
        using var source = new CancellationTokenSource();
        source.Cancel();
        using var cancelled = new DevelopRun(source.Token);
        context.Check(cancelled.IsCancelRequested, "run_state_pre_cancelled_token_is_latched");
        cancelled.Dispose();
        cancelled.Cancel();
        context.Check(!cancelled.IsCancelRequested, "run_state_dispose_makes_direct_cancel_harmless");
    }

    internal static void Verify(ContractTestContext context)
    {
        VerifyManaged(context);
        string temporaryRoot = Path.Combine(
            Path.GetTempPath(),
            $"negaflow-run-state-{Guid.NewGuid():N}");
        string absentSource = Path.Combine(temporaryRoot, "absent.tif");
        string destination = Path.Combine(temporaryRoot, "out.png");

        using (var cancellation = new CancellationTokenSource())
        {
            cancellation.Cancel();
            using var cancelled = new DevelopRun(cancellation.Token);
            context.Check(cancelled.IsCancelRequested, "run_state_token_latches_before_the_call");

            DevelopExportResult result = NativeDevelopExporter.Run(
                new DevelopExportRequest
                {
                    SourcePath = absentSource,
                    DestinationPath = destination,
                },
                cancelled);
            context.Check(!result.Succeeded, "cancelled_run_does_not_succeed");
            context.Check(result.Cancelled, "cancelled_run_is_reported_as_cancelled");
            context.Check(result.FailureName == "cancelled", "cancelled_run_failure_name");
            context.Check(!File.Exists(destination), "cancelled_run_writes_nothing");
        }

        // An untouched handle must not change the answer a plain call would have given.
        using (var untouched = new DevelopRun())
        {
            DevelopExportResult result = NativeDevelopExporter.Run(
                new DevelopExportRequest
                {
                    SourcePath = absentSource,
                    DestinationPath = destination,
                },
                untouched);
            context.Check(!result.Cancelled, "untouched_run_state_does_not_cancel");
            context.Check(
                result.FailedStage == DevelopExportStage.ObserveSourceBefore,
                "untouched_run_state_keeps_the_ordinary_failure");
        }

        var disposed = new DevelopRun();
        disposed.Dispose();
        context.Check(disposed.ProgressPermille == 0, "disposed_run_reads_zero_progress");
        context.Check(disposed.Stage == DevelopExportStage.None, "disposed_run_reads_no_stage");
        context.Check(!disposed.IsCancelRequested, "disposed_run_reads_no_cancellation");
        disposed.Cancel();
        disposed.Dispose();
        context.Check(true, "disposed_run_tolerates_cancel_and_second_dispose");
    }
}
