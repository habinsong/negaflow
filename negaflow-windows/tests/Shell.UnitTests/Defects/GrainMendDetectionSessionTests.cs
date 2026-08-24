using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using static Negaflow.Shell.UnitTests.TestAssert;
using static Negaflow.Shell.UnitTests.TestFrameFactory;

namespace Negaflow.Shell.UnitTests;

internal static class GrainMendDetectionSessionTests
{
    internal static void Run()
    {
        RedetectionFailureKeepsExistingReview();
        EmptyDetectionKeepsReusableRegionSession();
        AutomaticModeOutlivesReviewAndAcceptedSession();
        LastSourcePixelUsesMacSourceSizeCoordinates();
    }

    private static void RedetectionFailureKeepsExistingReview()
    {
        GrainMendWorkspaceState state = new();
        LibraryFrameSnapshot frame = Frame(new ManualBaseRgb(0.2, 0.2, 0.2)) with
        {
            Id = "frame-redetect",
        };
        state.ChangeFrame(frame.Id);
        GrainMendDetectionToken token = Token(frame);
        DefectRect roi = new(0.1, 0.2, 0.3, 0.4);
        FakeGrainMendReviewProposal proposal = Proposal();
        long firstGeneration = state.BeginDetection(
            frame.Id,
            labelKind: DefectEditLabelKind.Guided);
        Check(state.SetDetectedReview(
                proposal,
                token,
                frame.Id,
                firstGeneration,
                roi,
                automatic: false),
            "grain_mend_session_seeds_guided_review");
        state.EndDetection(frame.Id, firstGeneration);
        DefectPoint component = new(0.25, 0.25);
        Check(state.ToggleReviewAtRaw(component),
            "grain_mend_session_seeds_exclusion");
        GrainMendReviewSession originalReview = state.PendingReview!;
        DefectEditItem originalEdit = state.PendingEdit!;

        using DevelopRun run = new();
        long failedGeneration = state.BeginDetection(
            frame.Id,
            run,
            DefectEditLabelKind.Guided);
        Check(state.IsDetecting &&
              ReferenceEquals(state.PendingReview, originalReview) &&
              ReferenceEquals(state.PendingEdit, originalEdit) &&
              state.PendingRawRoi == roi &&
              state.PendingReview.IsExcludedAtRaw(component),
            "grain_mend_session_preserves_review_while_redetecting");

        // Faulted/Refused outcomes do not publish a replacement; the detector only ends
        // this generation and restores the existing overlay.
        state.EndDetection(frame.Id, failedGeneration);
        Check(!state.IsDetecting &&
              state.ActiveRegionKind == DefectEditLabelKind.Guided &&
              ReferenceEquals(state.PendingReview, originalReview) &&
              ReferenceEquals(state.PendingEdit, originalEdit) &&
              state.PendingRawRoi == roi &&
              state.PendingReview.IsExcludedAtRaw(component) &&
              proposal.DisposeCount == 0,
            "grain_mend_session_failed_redetect_keeps_review_exclusion_and_roi");
    }

    private static void EmptyDetectionKeepsReusableRegionSession()
    {
        GrainMendWorkspaceState state = new();
        state.ChangeFrame("frame-empty");
        DefectRect guidedRoi = new(0.0, 0.0, 1.0, 1.0);
        long guidedGeneration = state.BeginDetection(
            "frame-empty",
            labelKind: DefectEditLabelKind.Guided);
        Check(state.SetDetectedEmpty(
                "frame-empty",
                guidedGeneration,
                guidedRoi,
                automatic: false),
            "grain_mend_session_accepts_empty_guided_detection");
        state.EndDetection("frame-empty", guidedGeneration);
        Check(!state.IsReviewing && state.PendingEdit is null &&
              state.ActiveRegionKind == DefectEditLabelKind.Guided &&
              state.PendingRawRoi == guidedRoi,
            "grain_mend_session_full_frame_guided_detection_keeps_guided_mode_and_roi");
        GrainMendHudState guidedHud = GrainMendHudProjection.Create(
            hasFrame: true,
            isDetecting: false,
            pendingLabel: null,
            review: null,
            tool: GrainMendTool.Guided,
            activeRegionKind: state.ActiveRegionKind,
            hasRegionSession: state.PendingRawRoi is not null);
        Check(guidedHud.Mode == GrainMendHudMode.Reviewing &&
              !guidedHud.Automatic && guidedHud.Total == 0 &&
              guidedHud.TuningEnabled && !guidedHud.RemoveEnabled,
            "grain_mend_session_empty_guided_detection_keeps_tuning_hud");
        state.SetSensitivity("frame-empty", automatic: false, 0.8);
        Check(state.TakeSensitivityRedetectionRoi() == guidedRoi,
            "grain_mend_session_empty_guided_detection_redetects_same_roi");

        state.ClearPending();
        DefectRect wholeFrame = new(0.0, 0.0, 1.0, 1.0);
        long automaticGeneration = state.BeginDetection(
            "frame-empty",
            labelKind: DefectEditLabelKind.Automatic);
        Check(state.SetDetectedEmpty(
                "frame-empty",
                automaticGeneration,
                wholeFrame,
                automatic: true),
            "grain_mend_session_accepts_empty_automatic_detection");
        state.EndDetection("frame-empty", automaticGeneration);
        Check(state.ActiveRegionKind == DefectEditLabelKind.Automatic &&
              state.PendingRawRoi == wholeFrame,
            "grain_mend_session_empty_automatic_detection_stays_active");
        GrainMendHudState automaticHud = GrainMendHudProjection.Create(
            hasFrame: true,
            isDetecting: false,
            pendingLabel: null,
            review: null,
            tool: GrainMendTool.None,
            activeRegionKind: state.ActiveRegionKind,
            hasRegionSession: state.PendingRawRoi is not null);
        Check(automaticHud.Mode == GrainMendHudMode.Reviewing &&
              automaticHud.Automatic && automaticHud.Total == 0 &&
              automaticHud.TuningEnabled && !automaticHud.RemoveEnabled,
            "grain_mend_session_empty_automatic_detection_keeps_tuning_hud");
        state.ClearPending();
        GrainMendHudState automaticWaiting = GrainMendHudProjection.Create(
            hasFrame: true,
            isDetecting: false,
            pendingLabel: null,
            review: null,
            tool: GrainMendTool.None,
            activeRegionKind: state.ActiveRegionKind,
            hasRegionSession: state.PendingRawRoi is not null);
        Check(state.ActiveRegionKind == DefectEditLabelKind.Automatic &&
              state.PendingRawRoi is null && automaticWaiting.Mode == GrainMendHudMode.Waiting &&
              automaticWaiting.Automatic,
            "grain_mend_session_cancel_keeps_automatic_mode_waiting");
        state.ExitRegionMode();
        Check(state.ActiveRegionKind is null,
            "grain_mend_session_explicit_mode_exit_clears_automatic_mode");
    }

    private static void AutomaticModeOutlivesReviewAndAcceptedSession()
    {
        GrainMendWorkspaceState state = new();
        LibraryFrameSnapshot frame = Frame(new ManualBaseRgb(0.2, 0.2, 0.2)) with
        {
            Id = "frame-auto-mode",
        };
        state.ChangeFrame(frame.Id);
        GrainMendDetectionToken token = Token(frame);

        FakeGrainMendReviewProposal cancelledProposal = Proposal();
        long cancelledGeneration = state.BeginDetection(
            frame.Id,
            labelKind: DefectEditLabelKind.Automatic);
        Check(state.SetDetectedReview(
                cancelledProposal,
                token,
                frame.Id,
                cancelledGeneration,
                new DefectRect(0.0, 0.0, 1.0, 1.0),
                automatic: true),
            "grain_mend_auto_mode_prepares_cancelled_review");
        state.ClearPending();
        Check(!state.IsReviewing && cancelledProposal.DisposeCount == 1 &&
              state.ActiveRegionKind == DefectEditLabelKind.Automatic,
            "grain_mend_auto_mode_survives_review_cancel");

        FakeGrainMendReviewProposal acceptedProposal = Proposal();
        long acceptedGeneration = state.BeginDetection(
            frame.Id,
            labelKind: DefectEditLabelKind.Automatic);
        Check(state.SetDetectedReview(
                acceptedProposal,
                token,
                frame.Id,
                acceptedGeneration,
                new DefectRect(0.0, 0.0, 1.0, 1.0),
                automatic: true),
            "grain_mend_auto_mode_prepares_accepted_review");
        DefectEditItem? accepted = state.BuildAcceptedEdit();
        Check(accepted is not null && state.CommitAcceptedEdit(
                accepted,
                _ => LibraryFrameError.None) == LibraryFrameError.None &&
              !state.IsReviewing && acceptedProposal.DisposeCount == 1 &&
              state.ActiveRegionKind == DefectEditLabelKind.Automatic,
            "grain_mend_auto_mode_survives_successful_acceptance");
        state.ChangeFrame("frame-after-auto");
        Check(state.ActiveRegionKind is null && state.PendingFrameId is null,
            "grain_mend_auto_mode_does_not_cross_a_frame_change");
    }

    private static void LastSourcePixelUsesMacSourceSizeCoordinates()
    {
        FakeGrainMendReviewProposal proposal = new(
            4U,
            4U,
            [
                new GrainMendComponent(
                    GrainMendDefectClass.Dust,
                    0.9,
                    1UL,
                    3U,
                    3U,
                    1U,
                    1U,
                    [new GrainMendPreviewPoint(3U, 3U)]),
            ]);
        using GrainMendReviewSession review = GrainMendReviewSession.TryCreate(
            proposal,
            automatic: false) ?? throw new InvalidOperationException(
                "The edge-coordinate review fixture is invalid.");
        DefectPoint preview = review.PreviewEdit.Preview.Single().Points.Single();
        Check(preview == new DefectPoint(0.75, 0.75),
            "grain_mend_preview_last_pixel_uses_source_size_denominator");
        Check(review.ToggleAtRaw(preview) && review.IsExcludedAtRaw(preview),
            "grain_mend_review_click_round_trips_last_pixel_with_source_size");
        Check(!review.IsExcludedAtRaw(new DefectPoint(1.0, 1.0)),
            "grain_mend_review_unit_edge_is_outside_last_pixel");

        GrainMendMaskWindow legacy = new(
            4,
            4,
            new DefectRect(0.0, 0.0, 4.0, 4.0),
            new DefectSize(4.0, 4.0));
        Check(legacy.TryLocate(preview, out int x, out int y) && x == 3 && y == 3,
            "grain_mend_legacy_click_uses_source_size_coordinates");
        Check(!legacy.TryLocate(new DefectPoint(1.0, 1.0), out _, out _),
            "grain_mend_legacy_unit_edge_is_outside_last_pixel");
    }

    private static GrainMendDetectionToken Token(LibraryFrameSnapshot frame)
    {
        if (!GrainMendDetectionToken.TryCreate(frame, out GrainMendDetectionToken? token) ||
            token is null)
        {
            throw new InvalidOperationException("The detection token fixture is invalid.");
        }
        return token;
    }

    private static FakeGrainMendReviewProposal Proposal() => new(
        4U,
        4U,
        [
            new GrainMendComponent(
                GrainMendDefectClass.Dust,
                0.9,
                1UL,
                1U,
                1U,
                1U,
                1U,
                [new GrainMendPreviewPoint(1U, 1U)]),
        ]);
}
