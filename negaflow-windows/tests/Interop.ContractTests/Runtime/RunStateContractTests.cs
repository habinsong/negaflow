using System.Runtime.InteropServices;

namespace Negaflow.Interop.ContractTests;

internal static unsafe class RunStateContractTests
{
    internal static void Verify(ContractTestContext context)
    {
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
