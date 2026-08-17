using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

/// <summary>캔버스 위 캡슐이 지금 무엇을 보여야 하는지입니다.</summary>
public enum GrainMendHudMode
{
    /// <summary>결함 도구가 캔버스를 잡고 있지 않습니다.</summary>
    Hidden,

    /// <summary>가이드 도구를 켜 두고 아직 드래그를 기다립니다.</summary>
    Waiting,

    /// <summary>검출이 도는 중입니다.</summary>
    Detecting,

    /// <summary>검출 결과를 보고 있습니다.</summary>
    Reviewing,
}

/// <summary>
/// macOS <c>RegionDefectOverlay</c> 가 캔버스 위에 띄우는 캡슐과 종류별 칩의 상태입니다.
/// </summary>
/// <remarks>
/// macOS 는 이 줄을 <b>사진 위</b>에 띄웁니다 — 검출 결과를 보면서 손이 사진을 떠나지 않게
/// 하려는 배치입니다. 오른쪽 카드에 두면 시선이 사진과 패널을 오갑니다.
/// </remarks>
public sealed record GrainMendHudState(
    GrainMendHudMode Mode,
    bool Automatic,
    int Total,
    int Excluded,
    bool RemoveEnabled,
    bool TuningEnabled,
    IReadOnlyList<GrainMendClassSummary> Chips)
{
    public bool IsVisible => Mode != GrainMendHudMode.Hidden;

    /// <summary>남은(제외하지 않은) 결함 수입니다.</summary>
    public int Included => Total - Excluded;
}

/// <summary>
/// 캡슐이 무엇을 내는지 정하는 규칙입니다. 화면 밖에서 확인할 수 있어야 "검출은 됐는데 칩이
/// 안 뜬다" 같은 것을 창을 띄우지 않고 좁힐 수 있습니다.
/// </summary>
public static class GrainMendHudProjection
{
    /// <param name="hasFrame">고른 사진이 있는지.</param>
    /// <param name="isDetecting">검출이 도는 중인지.</param>
    /// <param name="pendingLabel">아직 받아들이지 않은 검출의 이름표. 없으면 검토 중이 아닙니다.</param>
    /// <param name="review">검토 세션. 성분 수·제외·종류별 요약이 여기서 나옵니다.</param>
    /// <param name="tool">지금 캔버스를 잡고 있는 도구.</param>
    public static GrainMendHudState Create(
        bool hasFrame,
        bool isDetecting,
        DefectEditLabelKind? pendingLabel,
        GrainMendReviewSession? review,
        GrainMendTool tool)
    {
        bool reviewing = pendingLabel is not null;
        bool automatic = pendingLabel == DefectEditLabelKind.Automatic;
        if (!hasFrame)
        {
            return Empty;
        }
        if (isDetecting)
        {
            return new GrainMendHudState(
                GrainMendHudMode.Detecting,
                automatic,
                Total: 0,
                Excluded: 0,
                RemoveEnabled: false,
                TuningEnabled: false,
                Chips: []);
        }
        if (reviewing)
        {
            int total = review?.ComponentCount ?? 0;
            int excluded = review?.ExcludedCount ?? 0;
            return new GrainMendHudState(
                GrainMendHudMode.Reviewing,
                automatic,
                total,
                excluded,
                // 모두 꺼 둔 검토를 받아들이면 아무것도 고치지 않는 항목이 남습니다.
                RemoveEnabled: total - excluded > 0,
                TuningEnabled: true,
                // macOS 는 검출 결과가 있을 때에만 칩 줄을 냅니다.
                Chips: review?.ClassSummaries() ?? []);
        }
        // 자동은 누르는 즉시 검출로 넘어갑니다. 기다리는 상태가 남는 것은 가이드뿐입니다.
        return tool == GrainMendTool.Guided
            ? new GrainMendHudState(
                GrainMendHudMode.Waiting,
                Automatic: false,
                Total: 0,
                Excluded: 0,
                RemoveEnabled: false,
                TuningEnabled: false,
                Chips: [])
            : Empty;
    }

    private static readonly GrainMendHudState Empty = new(
        GrainMendHudMode.Hidden,
        Automatic: false,
        Total: 0,
        Excluded: 0,
        RemoveEnabled: false,
        TuningEnabled: false,
        Chips: []);
}
