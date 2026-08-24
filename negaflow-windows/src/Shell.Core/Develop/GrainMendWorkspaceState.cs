using Negaflow.Catalog;
using Negaflow.Interop;

namespace Negaflow.Shell.Develop;

public enum GrainMendAcceptanceBuildKind
{
    Completed,
    Stale,
    Failed,
}

public sealed record GrainMendAcceptanceBuildResult(
    GrainMendAcceptanceBuildKind Kind,
    DefectEditItem? Edit);

public sealed class GrainMendAcceptance
{
    private readonly GrainMendReviewSession review;
    private readonly bool[] exclusionSnapshot;

    internal GrainMendAcceptance(
        GrainMendReviewSession review,
        GrainMendDetectionToken detectionToken,
        long generation)
    {
        this.review = review;
        exclusionSnapshot = review.CaptureExclusions();
        DetectionToken = detectionToken;
        Generation = generation;
    }

    public GrainMendDetectionToken DetectionToken { get; }

    internal long Generation { get; }

    internal GrainMendReviewSession Review => review;

    public Task<GrainMendAcceptanceBuildResult> BuildAsync(LibraryFrameSnapshot frame)
    {
        ArgumentNullException.ThrowIfNull(frame);
        return Task.Run(() =>
        {
            if (!DetectionToken.MatchesRecipe(frame))
            {
                return new GrainMendAcceptanceBuildResult(
                    GrainMendAcceptanceBuildKind.Stale,
                    null);
            }
            if (!TryBuildAcceptedEdit(out DefectEditItem? edit))
            {
                return new GrainMendAcceptanceBuildResult(
                    GrainMendAcceptanceBuildKind.Failed,
                    null);
            }
            if (!DetectionToken.MatchesRecipe(frame))
            {
                return new GrainMendAcceptanceBuildResult(
                    GrainMendAcceptanceBuildKind.Stale,
                    null);
            }
            return new GrainMendAcceptanceBuildResult(
                GrainMendAcceptanceBuildKind.Completed,
                edit);
        });
    }

    public bool TryBuildAcceptedEdit(out DefectEditItem? edit)
    {
        try
        {
            edit = review.BuildAcceptedEdit(exclusionSnapshot);
            return true;
        }
        catch (Exception error) when (error is
            ArgumentException or InvalidOperationException or ObjectDisposedException or OverflowException or
            NativeBootstrapException or DllNotFoundException or EntryPointNotFoundException or
            BadImageFormatException)
        {
            edit = null;
            return false;
        }
    }
}

/// <summary>
/// 한 Develop 작업공간에서 GrainMend 검출·검토·도구 입력 상태만 소유합니다. 검출 실행과 UI
/// 렌더링은 각각 coordinator와 view가 맡고, 이 타입은 frame별 옵션과 아직 확정되지 않은
/// review를 recipe 저장과 분리해 유지합니다.
/// </summary>
public sealed class GrainMendWorkspaceState
{
    private readonly Dictionary<string, SensitivityValues> sensitivityByFrame =
        new(StringComparer.Ordinal);
    private readonly Dictionary<string, MicroSpeckValues> microSpecksByFrame =
        new(StringComparer.Ordinal);
    private long detectionGeneration;
    private string? detectingFrameId;
    private DefectEditLabelKind? detectingLabelKind;
    private DefectEditLabelKind? activeRegionModeKind;
    private DevelopRun? detectingRun;
    private string? currentFrameId;

    public GrainMendStrokeSession Strokes { get; } = new();

    public DefectEditItem? PendingEdit { get; private set; }

    public GrainMendReviewSession? PendingReview { get; private set; }

    public DefectRect? PendingRawRoi { get; private set; }

    public string? PendingFrameId { get; private set; }

    public GrainMendDetectionToken? PendingDetectionToken { get; private set; }

    public bool IsDetecting { get; private set; }

    public DefectEditLabelKind? ActiveRegionKind =>
        detectingLabelKind ?? activeRegionModeKind ?? PendingEdit?.Label.Kind ??
        (Strokes.Tool == GrainMendTool.Guided ? DefectEditLabelKind.Guided : null);

    public bool IsReviewing => PendingReview is not null;

    public int IncludedCount => PendingReview?.IncludedCount ?? 0;

    public void BeginDetection()
    {
        BeginDetection(currentFrameId ?? string.Empty);
    }

    public long BeginDetection(
        string frameId,
        DevelopRun? run = null,
        DefectEditLabelKind? labelKind = null)
    {
        ArgumentNullException.ThrowIfNull(frameId);
        if (!string.Equals(currentFrameId, frameId, StringComparison.Ordinal))
        {
            currentFrameId = frameId;
            InvalidateDetectionAndReview(clearRegionMode: true);
        }
        CancelDetectingRun();
        detectionGeneration = checked(detectionGeneration + 1L);
        detectingFrameId = frameId;
        detectingLabelKind = labelKind;
        activeRegionModeKind = labelKind ?? activeRegionModeKind;
        detectingRun = run;
        IsDetecting = true;
        return detectionGeneration;
    }

    public void EndDetection()
    {
        detectingFrameId = null;
        detectingLabelKind = null;
        detectingRun = null;
        IsDetecting = false;
    }

    public void EndDetection(string frameId, long generation)
    {
        if (!OwnsDetection(frameId, generation))
        {
            return;
        }
        IsDetecting = false;
        detectingFrameId = null;
        detectingLabelKind = null;
        detectingRun = null;
    }

    public bool OwnsDetection(string frameId, long generation) =>
        IsDetecting && generation == detectionGeneration &&
        string.Equals(detectingFrameId, frameId, StringComparison.Ordinal) &&
        string.Equals(currentFrameId, frameId, StringComparison.Ordinal);

    public bool OwnsFrame(string? frameId) =>
        string.Equals(currentFrameId, frameId, StringComparison.Ordinal);

    public void ChangeFrame(string? frameId)
    {
        currentFrameId = frameId;
        Strokes.ChangeFrame(frameId);
        InvalidateDetectionAndReview(clearRegionMode: true);
    }

    public bool SetDetectedEdit(
        DefectEditItem edit,
        DefectRect rawRoi,
        bool falsePositiveRisk = false)
    {
        ArgumentNullException.ThrowIfNull(edit);
        GrainMendReviewSession? review = GrainMendReviewSession.TryCreate(
            edit, falsePositiveRisk);
        if (review is null)
        {
            return false;
        }
        ReleasePending();
        PendingEdit = edit;
        PendingReview = review;
        PendingRawRoi = rawRoi;
        PendingFrameId = currentFrameId;
        PendingDetectionToken = null;
        activeRegionModeKind = edit.Label.Kind;
        return true;
    }

    public bool SetDetectedReview(
        IGrainMendReviewProposal proposal,
        GrainMendDetectionToken detectionToken,
        string frameId,
        long generation,
        DefectRect rawRoi,
        bool automatic,
        bool falsePositiveRisk = false)
    {
        ArgumentNullException.ThrowIfNull(proposal);
        ArgumentNullException.ThrowIfNull(detectionToken);
        if (!string.Equals(detectionToken.FrameId, frameId, StringComparison.Ordinal) ||
            !OwnsDetection(frameId, generation))
        {
            proposal.Dispose();
            return false;
        }

        GrainMendReviewSession? review;
        try
        {
            review = GrainMendReviewSession.TryCreate(
                proposal, automatic, falsePositiveRisk);
        }
        catch
        {
            proposal.Dispose();
            throw;
        }
        if (review is null)
        {
            proposal.Dispose();
            return false;
        }

        ReleasePending();
        PendingEdit = review.PreviewEdit;
        PendingReview = review;
        PendingRawRoi = rawRoi;
        PendingFrameId = frameId;
        PendingDetectionToken = detectionToken;
        activeRegionModeKind = automatic
            ? DefectEditLabelKind.Automatic
            : DefectEditLabelKind.Guided;
        return true;
    }

    /// <summary>
    /// 정상적으로 끝났지만 component가 0개인 검출도 활성 region session과 ROI를 소유합니다.
    /// macOS의 빈 <c>DefectLabelField</c>와 같은 상태라 민감도 변경이 같은 ROI를 다시 씁니다.
    /// </summary>
    public bool SetDetectedEmpty(
        string frameId,
        long generation,
        DefectRect rawRoi,
        bool automatic)
    {
        ArgumentNullException.ThrowIfNull(frameId);
        if (!OwnsDetection(frameId, generation))
        {
            return false;
        }

        ReleasePending();
        PendingRawRoi = rawRoi;
        PendingFrameId = frameId;
        activeRegionModeKind = automatic
            ? DefectEditLabelKind.Automatic
            : DefectEditLabelKind.Guided;
        return true;
    }

    public void ClearPending()
    {
        InvalidateDetectionAndReview(clearRegionMode: false);
    }

    public void ExitRegionMode()
    {
        InvalidateDetectionAndReview(clearRegionMode: true);
    }

    public bool ToggleReviewAtRaw(DefectPoint rawPoint) =>
        PendingReview?.ToggleAtRaw(rawPoint) == true;

    public DefectEditItem? BuildAcceptedEdit() =>
        PendingReview is null ? PendingEdit : PendingReview.BuildAcceptedEdit();

    public bool TryBuildAcceptedEdit(out DefectEditItem? edit)
    {
        try
        {
            edit = BuildAcceptedEdit();
            return true;
        }
        catch (Exception error) when (error is
            ArgumentException or InvalidOperationException or OverflowException or
            NativeBootstrapException or DllNotFoundException or EntryPointNotFoundException or
            BadImageFormatException)
        {
            edit = null;
            return false;
        }
    }

    public GrainMendAcceptance? CaptureAcceptance() =>
        PendingReview is { } review && PendingDetectionToken is { } token &&
        string.Equals(PendingFrameId, token.FrameId, StringComparison.Ordinal)
            ? new GrainMendAcceptance(review, token, detectionGeneration)
            : null;

    public bool OwnsAcceptance(GrainMendAcceptance acceptance)
    {
        ArgumentNullException.ThrowIfNull(acceptance);
        return acceptance.Generation == detectionGeneration &&
            ReferenceEquals(PendingReview, acceptance.Review) &&
            ReferenceEquals(PendingDetectionToken, acceptance.DetectionToken) &&
            string.Equals(PendingFrameId, acceptance.DetectionToken.FrameId, StringComparison.Ordinal) &&
            string.Equals(currentFrameId, acceptance.DetectionToken.FrameId, StringComparison.Ordinal);
    }

    public LibraryFrameError CommitAcceptedEdit(
        DefectEditItem edit,
        Func<DefectEditItem, LibraryFrameError> persist)
    {
        ArgumentNullException.ThrowIfNull(edit);
        ArgumentNullException.ThrowIfNull(persist);
        LibraryFrameError error = persist(edit);
        if (error == LibraryFrameError.None)
        {
            ClearPending();
        }
        return error;
    }

    public double Sensitivity(string frameId, bool automatic)
    {
        if (!sensitivityByFrame.TryGetValue(frameId, out SensitivityValues values))
        {
            return GrainMendSensitivity.Default;
        }
        return automatic ? values.Automatic : values.Guided;
    }

    public void SetSensitivity(string frameId, bool automatic, double value)
    {
        SensitivityValues prior = sensitivityByFrame.TryGetValue(frameId, out SensitivityValues values)
            ? values
            : SensitivityValues.Default;
        double clamped = GrainMendSensitivity.Clamp(value);
        sensitivityByFrame[frameId] = automatic
            ? prior with { Automatic = clamped }
            : prior with { Guided = clamped };
        SensitivityChanged = true;
    }

    public bool MicroSpecks(
        string frameId,
        bool automatic,
        bool automaticDefault,
        bool guidedDefault)
    {
        if (!microSpecksByFrame.TryGetValue(frameId, out MicroSpeckValues values))
        {
            return automatic ? automaticDefault : guidedDefault;
        }
        return automatic ? values.Automatic : values.Guided;
    }

    public void SetMicroSpecks(
        string frameId,
        bool automatic,
        bool enabled,
        bool automaticDefault,
        bool guidedDefault)
    {
        MicroSpeckValues prior = microSpecksByFrame.TryGetValue(frameId, out MicroSpeckValues values)
            ? values
            : new MicroSpeckValues(automaticDefault, guidedDefault);
        microSpecksByFrame[frameId] = automatic
            ? prior with { Automatic = enabled }
            : prior with { Guided = enabled };
    }

    public bool SensitivityChanged { get; private set; }

    public DefectRect? TakeSensitivityRedetectionRoi()
    {
        if (!SensitivityChanged || PendingRawRoi is not { } rawRoi)
        {
            return null;
        }
        SensitivityChanged = false;
        return rawRoi;
    }

    private readonly record struct SensitivityValues(double Automatic, double Guided)
    {
        public static SensitivityValues Default { get; } = new(
            GrainMendSensitivity.Default,
            GrainMendSensitivity.Default);
    }

    private readonly record struct MicroSpeckValues(bool Automatic, bool Guided);

    private void InvalidateDetectionAndReview(bool clearRegionMode)
    {
        CancelDetectingRun();
        detectionGeneration = checked(detectionGeneration + 1L);
        detectingFrameId = null;
        detectingLabelKind = null;
        if (clearRegionMode)
        {
            activeRegionModeKind = null;
        }
        IsDetecting = false;
        ReleasePending();
    }

    private void CancelDetectingRun()
    {
        detectingRun?.Cancel();
        detectingRun = null;
    }

    private void ReleasePending()
    {
        PendingReview?.Dispose();
        PendingEdit = null;
        PendingReview = null;
        PendingRawRoi = null;
        PendingFrameId = null;
        PendingDetectionToken = null;
        SensitivityChanged = false;
    }
}
