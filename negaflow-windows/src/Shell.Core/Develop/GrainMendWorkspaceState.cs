using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

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

    public GrainMendStrokeSession Strokes { get; } = new();

    public DefectEditItem? PendingEdit { get; private set; }

    public GrainMendReviewSession? PendingReview { get; private set; }

    public DefectRect? PendingRawRoi { get; private set; }

    public bool IsDetecting { get; private set; }

    public bool IsReviewing => PendingEdit is not null;

    public int IncludedCount => PendingReview?.IncludedCount ?? 0;

    public void BeginDetection()
    {
        ClearPending();
        IsDetecting = true;
    }

    public void EndDetection() => IsDetecting = false;

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
        PendingEdit = edit;
        PendingReview = review;
        PendingRawRoi = rawRoi;
        return true;
    }

    public void ClearPending()
    {
        PendingEdit = null;
        PendingReview = null;
        PendingRawRoi = null;
        SensitivityChanged = false;
    }

    public bool ToggleReviewAtRaw(DefectPoint rawPoint) =>
        PendingReview?.ToggleAtRaw(rawPoint) == true;

    public DefectEditItem? BuildAcceptedEdit() =>
        PendingReview is null ? PendingEdit : PendingReview.BuildAcceptedEdit();

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
}
