using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using static Negaflow.Shell.UnitTests.TestAssert;

namespace Negaflow.Shell.UnitTests;

/// <summary>
/// IR 결함 제거 한 번이 무엇을 말하는지 고정합니다. macOS
/// <c>applyInfraredDetection</c> 의 <c>statusMessage</c> 분기와 같아야 합니다 — 이것이
/// 없으면 IR 이 왜 건너뛰었는지 사용자가 알 방법이 없습니다.
/// </summary>
internal static class InfraredCleanStatusTests
{
    public static void Run()
    {
        VerifyAppliedCarriesTheDefectCount();
        VerifyAppliedWithoutComponentsFallsBackToNoDefects();
        VerifyRefusalsMapToTheirOwnMessage();
        VerifyCancelledAndDuplicateStaySilent();
        VerifyEveryOtherFailureReadsAsFailed();
        VerifySelectedFrameOwnsAsyncStatus();
    }

    private static void VerifySelectedFrameOwnsAsyncStatus()
    {
        using var host = new LibraryHostService(
            new ImmediateUiDispatcher(),
            new FakeExporter(_ => DevelopTestResults.FailedResult("unused")));
        var state = new DevelopInfraredCleanState(host);
        state.BindFrame("frame-a");
        Check(state.Update("frame-a", InfraredCleanStatus.Detecting) &&
              state.Status.Message == InfraredCleanMessage.Detecting,
            "infrared_status_selected_frame_accepts_async_update");
        state.BindFrame("frame-a");
        Check(state.Status.Message == InfraredCleanMessage.Detecting,
            "infrared_status_same_frame_refresh_preserves_message");
        state.BindFrame("frame-b");
        Check(state.Status == InfraredCleanStatus.Silent &&
              !state.Update("frame-a", InfraredCleanStatus.Detecting),
            "infrared_status_photo_switch_rejects_stale_message");
    }

    private static void VerifyAppliedCarriesTheDefectCount()
    {
        InfraredCleanStatus status = InfraredCleanStatus.From(
            Result(InfraredDefectApplyStatus.Applied, componentCount: 7));
        Check(
            status.Message == InfraredCleanMessage.Applied && status.DefectCount == 7,
            "infrared_status_applied_reports_the_count");
    }

    private static void VerifyAppliedWithoutComponentsFallsBackToNoDefects()
    {
        // macOS 도 성공했는데 성분이 비면 "찾지 못했다" 로 내려앉습니다.
        InfraredCleanStatus status = InfraredCleanStatus.From(
            Result(InfraredDefectApplyStatus.Applied, componentCount: 0));
        Check(
            status.Message == InfraredCleanMessage.NoDefects && status.DefectCount == 0,
            "infrared_status_applied_without_components_reads_as_no_defects");
    }

    private static void VerifyRefusalsMapToTheirOwnMessage()
    {
        Check(
            InfraredCleanStatus.From(Result(InfraredDefectApplyStatus.NoDefects)).Message ==
                InfraredCleanMessage.NoDefects,
            "infrared_status_no_defects");
        Check(
            InfraredCleanStatus.From(Result(InfraredDefectApplyStatus.CoverageTooHigh)).Message ==
                InfraredCleanMessage.CoverageAborted,
            "infrared_status_coverage_aborted");
        Check(
            InfraredCleanStatus.From(Result(InfraredDefectApplyStatus.UnsupportedFilm)).Message ==
                InfraredCleanMessage.UnsupportedFilm,
            "infrared_status_unsupported_film");
    }

    private static void VerifyCancelledAndDuplicateStaySilent()
    {
        Check(
            InfraredCleanStatus.From(Result(InfraredDefectApplyStatus.Cancelled)).Message ==
                InfraredCleanMessage.None,
            "infrared_status_cancelled_is_silent");
        Check(
            InfraredCleanStatus.From(Result(InfraredDefectApplyStatus.AlreadyApplied)).Message ==
                InfraredCleanMessage.None,
            "infrared_status_already_applied_is_silent");
        Check(
            InfraredCleanStatus.From(null).Message == InfraredCleanMessage.None,
            "infrared_status_without_a_run_is_silent");
    }

    private static void VerifyEveryOtherFailureReadsAsFailed()
    {
        foreach (InfraredDefectApplyStatus status in new[]
        {
            InfraredDefectApplyStatus.DetectionFailed,
            InfraredDefectApplyStatus.PersistenceFailed,
            InfraredDefectApplyStatus.InvalidFrame,
            InfraredDefectApplyStatus.SourceMismatch,
        })
        {
            Check(
                InfraredCleanStatus.From(Result(status)).Message ==
                    InfraredCleanMessage.Failed,
                $"infrared_status_{status}_reads_as_failed");
        }
    }

    private static InfraredDefectApplyResult Result(
        InfraredDefectApplyStatus status,
        int componentCount = 0)
    {
        InfraredDetectionResult? detection = status != InfraredDefectApplyStatus.Applied
            ? null
            : new InfraredDetectionResult(
                InfraredDetectionStatus.Ok,
                Width: 16U,
                Height: 16U,
                OffsetX: 0,
                OffsetY: 0,
                AlignmentStatus: InfraredAlignmentStatus.Aligned,
                AlignmentSearchRadius: 0U,
                AlignmentDownsampleFactor: 1U,
                AlignmentPeakCorrelation: 0.0,
                AlignmentRunnerUpCorrelation: 0.0,
                Coverage: 0.0,
                MedianGain: 0.0,
                CandidateCount: (ulong)componentCount,
                ConfirmedCount: (ulong)componentCount,
                Clusters: [],
                Components: [.. Enumerable.Range(0, componentCount).Select(_ =>
                    new InfraredDetectedComponent(
                        InfraredDefectClass.Dust,
                        Confidence: 1.0,
                        Area: 4UL,
                        PreviewPoints: []))]);
        return new InfraredDefectApplyResult(
            status,
            detection,
            null,
            DefectSidecarError.None,
            CatalogStoreError.None);
    }
}
