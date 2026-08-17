using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

/// <summary>
/// 행 왼쪽의 종류 아이콘입니다. macOS 는 SF Symbol 이름을 직접 쓰지만 Windows 글리프는 화면이
/// 고르므로, 여기서는 무엇을 뜻하는지만 정합니다.
/// </summary>
public enum DefectLayerIcon
{
    /// <summary>macOS <c>paintbrush.pointed.fill</c>.</summary>
    Brush,

    /// <summary>macOS <c>rectangle.on.rectangle</c>.</summary>
    Clone,

    /// <summary>macOS <c>scope</c> — 자동·가이드·IR 이 모두 이것입니다.</summary>
    Region,
}

/// <summary>목록 한 줄입니다. macOS <c>DefectLayerRow</c> 가 그리는 값과 같습니다.</summary>
public sealed record DefectLayerRow(
    Guid Id,
    int DisplayIndex,
    bool Enabled,
    double Strength,
    string Title,
    string Summary,
    DefectLayerIcon Icon,
    bool MaskShown);

/// <summary>
/// macOS <c>LibraryDefectReviewTracking</c> 에서 완료 판정에 쓰는 세 값입니다. 셋이 모두 현재
/// identity 와 같아야 검토가 끝난 것입니다 — 원본이 바뀌면 같은 recipe 해시라도 승계하지
/// 않습니다.
/// </summary>
public readonly record struct DefectReviewMark(
    ulong RecipeRevision,
    string RecipeSha256,
    string SourceIdentitySha256);

/// <summary>섹션 전체가 한 번에 내는 상태입니다.</summary>
public sealed record DefectLayerSectionState(
    bool Visible,
    int Count,
    IReadOnlyList<DefectLayerRow> Rows,
    bool Scrolls,
    double ScrollMaximumHeight,
    bool DoneVisible,
    bool DoneEnabled,
    bool Reviewed);

/// <summary>
/// 적용된 결함 제거를 "복원 레이어" 목록으로 투영합니다. macOS
/// <c>DefectLayerSection.swift</c> 의 규칙을 그대로 옮긴 것이며, 화면 배치와 다른 이유로
/// 바뀌므로 뷰 밖에 둡니다.
/// </summary>
public static class DefectLayerProjection
{
    /// <summary>이 수를 넘으면 목록이 스크롤합니다. macOS <c>visibleLayerLimit</c>.</summary>
    public const int VisibleLayerLimit = 5;

    /// <summary>macOS <c>estimatedLayerRowHeight</c>.</summary>
    public const double EstimatedRowHeight = 54.0;

    /// <param name="maskPreviewId">마스크를 보여 주는 항목입니다. macOS <c>defectMaskPreviewID</c>.</param>
    /// <param name="reviewed">저장된 검토 완료 기록입니다. 없으면 완료 단추가 눌립니다.</param>
    /// <param name="isRemovingDefects">수리를 다시 만드는 중이면 켜기·삭제·완료를 막습니다.</param>
    public static DefectLayerSectionState Create(
        LibraryFrameSnapshot? frame,
        DefectLayerText text,
        Guid? maskPreviewId,
        DefectReviewMark? reviewed,
        bool isRemovingDefects)
    {
        ArgumentNullException.ThrowIfNull(text);
        // macOS 는 frame.defectEdits 가 비면 섹션 자체를 내지 않습니다.
        if (frame?.DefectRecipe is not { Items.Count: > 0 } recipe)
        {
            return new DefectLayerSectionState(
                Visible: false,
                Count: 0,
                Rows: [],
                Scrolls: false,
                ScrollMaximumHeight: 0.0,
                DoneVisible: false,
                DoneEnabled: false,
                Reviewed: false);
        }

        List<DefectLayerRow> rows = new(recipe.Items.Count);
        for (int index = 0; index < recipe.Items.Count; ++index)
        {
            DefectEditItem item = recipe.Items[index];
            rows.Add(new DefectLayerRow(
                item.Id,
                index + 1,
                item.Enabled,
                item.Strength,
                text.Title(item.Label),
                text.Summary(item.Summary),
                Icon(item.Kind),
                maskPreviewId == item.Id));
        }

        // macOS boundDefectRecipeIdentity: 원본에 묶이지 않은 recipe 는 완료를 물을 수 없습니다.
        bool bound = recipe.SourceIdentity is not null;
        bool isReviewed = bound && IsReviewed(recipe, reviewed);
        return new DefectLayerSectionState(
            Visible: true,
            Count: rows.Count,
            Rows: rows,
            Scrolls: rows.Count > VisibleLayerLimit,
            ScrollMaximumHeight: EstimatedRowHeight * VisibleLayerLimit,
            DoneVisible: bound,
            DoneEnabled: bound && !isReviewed && !isRemovingDefects,
            Reviewed: isReviewed);
    }

    /// <summary>
    /// 목록이 바뀐 뒤에도 그 항목이 남아 있을 때만 마스크 표시를 유지합니다. macOS 는 레이어가
    /// 사라지면 <c>defectMaskPreviewID</c> 를 지웁니다 — 없는 항목의 마스크는 그릴 수 없습니다.
    /// </summary>
    public static Guid? SurvivingMaskPreview(
        LibraryFrameSnapshot? frame,
        Guid? maskPreviewId)
    {
        if (maskPreviewId is not { } id)
        {
            return null;
        }
        return frame?.DefectRecipe?.Items.Any(item => item.Id == id) == true ? id : null;
    }

    private static bool IsReviewed(DefectRecipeSnapshot recipe, DefectReviewMark? reviewed) =>
        reviewed is { } mark &&
        recipe.SourceIdentity is { } source &&
        mark.RecipeRevision == recipe.RecipeRevision &&
        string.Equals(mark.RecipeSha256, recipe.RecipeSha256, StringComparison.Ordinal) &&
        string.Equals(mark.SourceIdentitySha256, source.Sha256, StringComparison.Ordinal);

    private static DefectLayerIcon Icon(DefectEditKind kind) => kind switch
    {
        DefectEditKind.Brush => DefectLayerIcon.Brush,
        DefectEditKind.Clone => DefectLayerIcon.Clone,
        _ => DefectLayerIcon.Region,
    };
}
