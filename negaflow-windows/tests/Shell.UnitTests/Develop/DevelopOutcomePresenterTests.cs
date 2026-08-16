using Negaflow.Interop;
using Negaflow.Shell.Develop;
using static Negaflow.Shell.UnitTests.DevelopTestResults;
using static Negaflow.Shell.UnitTests.TestAssert;

namespace Negaflow.Shell.UnitTests;

internal static class DevelopOutcomePresenterTests
{
    public static void Run()
    {
        Check(
            DevelopPanelState.Describe(
                new DevelopExportOutcome(DevelopExportOutcomeKind.Completed, OkResult(), DevelopRequestRefusal.None, null)).Contains("100×50"),
            "describe_success_has_dimensions");

        // "Export failed" 만 보여 주면 사용자는 스캔을 다시 하는 것 말고 할 게 없습니다.
        string decodeFailure = DevelopPanelState.Describe(
            DevelopExportOutcome.Completed(
                FailedResult(DevelopExportStage.Decode, "unsupported_compression")));
        Check(decodeFailure.Contains("decoding"), "describe_failure_names_stage");
        Check(
            decodeFailure.Contains("unsupported_compression"),
            "describe_failure_keeps_engine_reason");

        string missingFile = DevelopPanelState.Describe(
            DevelopExportOutcome.Completed(
                FailedResult(DevelopExportStage.ObserveSourceBefore, "file_not_found")));
        Check(
            missingFile.Contains("reading the source file"),
            "describe_missing_file_stage");

        Check(
            DevelopPanelState.Describe(
                DevelopExportOutcome.Refused(DevelopRequestRefusal.MissingManualBase))
                .Contains("Dmin"),
            "describe_missing_base_says_what_to_do");
        Check(
            DevelopPanelState.Describe(
                DevelopExportOutcome.Refused(DevelopRequestRefusal.UnsupportedDigitalSource))
                .Contains("rendered digital"),
            "describe_digital_source");
        Check(
            DevelopPanelState.Describe(DevelopExportOutcome.Faulted("engine gone"))
                .Contains("engine gone"),
            "describe_fault_keeps_message");
        Check(
            DevelopPanelState.Describe(DevelopExportOutcome.Busy())
                .Contains("already running"),
            "describe_busy");
    }
}
