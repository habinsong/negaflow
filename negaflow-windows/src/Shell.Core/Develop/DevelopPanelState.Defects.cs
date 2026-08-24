using Negaflow.Catalog;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell;

/// <summary>
/// GrainMend 다섯 도구가 <c>DevelopPanelState</c> 를 통해 쓰는 표면입니다. 획 조립·검토
/// 수락·되돌리기·검토 완료가 여기 모입니다.
/// </summary>
/// <remarks>
/// 왜 나누는가 — 결함 편집은 base·톤·색과 <b>다른 이유로</b> 바뀝니다. 한 파일에 두면
/// 500줄 규칙을 넘고, 무엇보다 GrainMend 를 고칠 때마다 현상 전체가 걸린 파일을 건드리게
/// 됩니다. 상태(선택 frame)는 그대로 한 객체가 소유하므로 부분 클래스로 나눕니다.
/// </remarks>
public sealed partial class DevelopPanelState
{
    /// <summary>
    /// macOS GrainMend 브러시의 기본 굵기입니다. 짧은 변에 대한 비율입니다.
    /// </summary>
    public const double DefaultBrushThickness = 0.01;

    /// <summary>macOS 복제 도장의 기본 지름입니다. 원본 raw 화소 단위입니다.</summary>
    public const double DefaultCloneDiameterPixels = 48.0;

    public const double MinimumCloneDiameterPixels = 4.0;

    public const double MaximumCloneDiameterPixels = 512.0;

    /// <summary>
    /// 캔버스에서 그은 치유 브러시 획 하나를 남깁니다. 점은 <b>표시 좌표</b>로 받고 여기서
    /// 원본 좌표로 되돌립니다 — 호출부가 좌표계를 알 필요가 없어야 어긋날 자리가 줄어듭니다.
    /// </summary>
    public LibraryFrameError AddBrushStroke(
        IReadOnlyList<DefectPoint> displayPoints,
        double thickness = DefaultBrushThickness)
    {
        DevelopDefectEditResult result = defectEditor.AddBrushStroke(
            SelectedFrame,
            displayPoints,
            thickness);
        return RefreshAfterDefectEdit(result);
    }

    /// <summary>
    /// 복제 도장 획 하나입니다. 원본 점은 표시 좌표로 받으며, 변위는 원본 공간에서 계산합니다 —
    /// 표시 공간에서 뺀 변위는 회전·수평보정이 걸린 프레임에서 방향이 틀어집니다.
    /// </summary>
    public LibraryFrameError AddCloneStroke(
        IReadOnlyList<DefectPoint> displayPoints,
        DefectPoint displaySourceAnchor,
        double diameter = DefaultCloneDiameterPixels) =>
        AddCloneStroke(
            displayPoints,
            displaySourceAnchor,
            alignedRawOffset: null,
            out _,
            diameter,
            DefectStrokeRecipeBuilder.DefaultCloneHardness);

    /// <summary>
    /// 첫 획에서 확정한 원본 공간 오프셋을 이후 획에도 그대로 씁니다. macOS 복제 도장은
    /// 소스가 브러시를 따라 움직이므로, 새 획의 시작점마다 소스 앵커와의 변위를 다시 계산하면
    /// 복제 위치가 튑니다.
    /// </summary>
    public LibraryFrameError AddCloneStroke(
        IReadOnlyList<DefectPoint> displayPoints,
        DefectPoint displaySourceAnchor,
        DefectPoint? alignedRawOffset,
        out DefectPoint usedRawOffset,
        double diameter = DefaultCloneDiameterPixels,
        double hardness = DefectStrokeRecipeBuilder.DefaultCloneHardness)
    {
        DevelopDefectEditResult result = defectEditor.AddCloneStroke(
            SelectedFrame,
            displayPoints,
            displaySourceAnchor,
            alignedRawOffset,
            out usedRawOffset,
            diameter,
            hardness,
            MinimumCloneDiameterPixels,
            MaximumCloneDiameterPixels);
        return RefreshAfterDefectEdit(result);
    }

    /// <summary>
    /// 검토를 마친 검출 결과를 recipe 에 담습니다. 자동·가이드는 이 호출 전까지 사진을
    /// 바꾸지 않습니다 — macOS 와 같은 상태 전환입니다.
    /// </summary>
    public LibraryFrameError AcceptDefectRegion(DefectEditItem edit)
    {
        DevelopDefectEditResult result = defectEditor.AcceptRegion(SelectedFrame, edit);
        return RefreshAfterDefectEdit(result);
    }

    public LibraryFrameError AddBrushStrokes(IReadOnlyList<DefectStroke> displayStrokes)
    {
        DevelopDefectEditResult result = defectEditor.AddBrushStrokes(
            SelectedFrame,
            displayStrokes);
        return RefreshAfterDefectEdit(result);
    }

    public LibraryFrameError AcceptDefectRegion(
        DefectEditItem edit,
        GrainMendDetectionToken detectionToken,
        LibraryFrameSnapshot validatedFrame)
    {
        ArgumentNullException.ThrowIfNull(edit);
        ArgumentNullException.ThrowIfNull(detectionToken);
        ArgumentNullException.ThrowIfNull(validatedFrame);
        if (!ReferenceEquals(
                GrainMendFrameSnapshot(detectionToken.FrameId),
                validatedFrame))
        {
            return LibraryFrameError.InvalidDefectRecipe;
        }
        DevelopDefectEditResult result = defectEditor.AcceptRegion(
            validatedFrame,
            edit,
            detectionToken,
            validatedFrame.DefectRecipe);
        return RefreshAfterDefectEdit(result);
    }

    /// <summary>
    /// macOS <c>ScanFrame.canUndoDefects</c>(= <c>defectHistoryDepth &gt; 0</c>)와 같이 현재
    /// 프레임에 접근 가능한 GrainMend 이력이 남았는지입니다. 실제 실행은 양쪽 모두 문서 공용
    /// undo stack의 마지막 동작을 되돌립니다.
    /// </summary>
    public bool CanUndoDefectEdit =>
        SelectedFrame is { } frame && host.CanUndoDefectFrame(frame.Id);

    public CatalogStoreError HistoryStoreError => host.StoreError;

    public DefectSidecarError HistorySidecarError => host.DefectSidecarError;

    /// <summary>
    /// macOS <c>performUndo</c> — 결함 편집 한 칸을 되돌립니다. 캡슐의 되돌리기 단추가
    /// 부르며, 되돌린 뒤 현상 화면이 새 상태를 다시 읽도록 프레임을 다시 고릅니다.
    /// </summary>
    public bool UndoDefectEdit()
    {
        if (!CanUndoDefectEdit || host.Undo() is null)
        {
            return false;
        }
        if (SelectedFrame is { } frame)
        {
            Select(frame.Id);
        }
        return true;
    }

    /// <summary>
    /// macOS <c>markDefectRecipeReviewed</c> — 지금 화면의 recipe 판을 "검토 완료"로 적습니다.
    /// 원본에 묶이지 않은 recipe 는 물을 수 없으므로 아무 일도 하지 않습니다.
    /// </summary>
    public LibraryFrameError MarkDefectRecipeReviewed()
    {
        LibraryFrameSnapshot? frame = DefectLayers.PreviewFrame;
        if (frame?.IsPreviewScan == true)
        {
            return LibraryFrameError.None;
        }
        if (frame is not { DefectRecipe: { SourceIdentity: { } source } recipe })
        {
            return LibraryFrameError.MissingId;
        }
        DefectReviewMarkRecord mark = new(
            recipe.RecipeRevision,
            recipe.RecipeSha256,
            source.Sha256);
        LibraryFrameError error = host.EditFrameRecord(
            frame.Id,
            record => DefectReviewTrackingCodec.Apply(record, mark));
        if (error == LibraryFrameError.None)
        {
            Select(frame.Id);
        }
        return error;
    }

    public bool HasDefectEdits(DefectEditKind kind) =>
        DevelopDefectEditor.HasEdits(SelectedFrame, kind);

    public bool HasDefectEdits(DefectEditLabelKind label) =>
        DevelopDefectEditor.HasEdits(SelectedFrame, label);

    public LibraryFrameSnapshot? GrainMendFrameSnapshot(string frameId)
    {
        ArgumentNullException.ThrowIfNull(frameId);
        if (!string.Equals(SelectedFrame?.Id, frameId, StringComparison.Ordinal))
        {
            return null;
        }
        foreach (LibraryFrameSnapshot frame in host.Frames)
        {
            if (string.Equals(frame.Id, frameId, StringComparison.Ordinal))
            {
                return frame;
            }
        }
        return null;
    }

    /// <summary>
    /// 한 도구가 남긴 편집만 지웁니다. 다른 도구의 편집과 자동 검출 결과는 남습니다 — macOS 의
    /// 도구별 초기화와 같습니다.
    /// </summary>
    public LibraryFrameError RemoveDefectEdits(DefectEditKind kind)
    {
        DevelopDefectEditResult result = defectEditor.RemoveEdits(SelectedFrame, kind);
        return RefreshAfterDefectEdit(result);
    }

    /// <summary>Resets just one visible GrainMend tool without discarding its siblings.</summary>
    public LibraryFrameError RemoveDefectEdits(DefectEditLabelKind label)
    {
        DevelopDefectEditResult result = defectEditor.RemoveEdits(SelectedFrame, label);
        return RefreshAfterDefectEdit(result);
    }

    /// <summary>macOS <c>clearAllDefects</c> — 측정된 IR은 보존하고 나머지 적용 결함을 지웁니다.</summary>
    public LibraryFrameError RemoveNonInfraredDefectEdits()
    {
        DevelopDefectEditResult result = defectEditor.RemoveNonInfraredEdits(SelectedFrame);
        return RefreshAfterDefectEdit(result);
    }

    /// <summary>
    /// Maps a display-space, top-first normalized rectangle to the smallest axis-aligned
    /// raw rectangle that contains all four inverse-transformed corners. Region defect
    /// recipes are raw-space data, so persisting the display rectangle directly would
    /// repair the wrong pixels after rotation, crop, or straighten.
    /// </summary>
    public bool TryMapDisplayRectToRaw(DefectRect displayRect, out DefectRect rawRect)
    {
        return DevelopDefectEditor.TryMapDisplayRectToRaw(
            SelectedFrame,
            displayRect,
            out rawRect);
    }

    internal LibraryFrameError RefreshAfterDefectEdit(DevelopDefectEditResult result)
    {
        if (result.Changed && SelectedFrame is { } frame)
        {
            Select(frame.Id);
        }
        return result.Error;
    }
}
