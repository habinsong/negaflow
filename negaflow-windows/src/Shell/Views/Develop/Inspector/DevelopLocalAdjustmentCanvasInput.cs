using Microsoft.UI.Xaml.Input;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell.Views.Develop.Inspector;

/// <summary>
/// macOS <c>LocalAdjustmentOverlay</c> 의 제스처 층입니다 — 사진 위에 끌어 마스크를 만듭니다.
/// </summary>
/// <remarks>
/// <para>
/// 브러시는 끄는 동안 점을 쌓고, 방사형·선형은 시작점과 끝점 둘만 쓰며, 다각형은 끌지 않고
/// 누를 때마다 꼭짓점을 찍었다가 세 개가 모이면 완료할 수 있습니다.
/// </para>
/// <para>
/// 좌표는 캔버스가 이미 원본 기준 0...1 로 내주므로(<c>CropDisplayPoint</c>) 그대로 씁니다.
/// </para>
/// </remarks>
internal sealed class DevelopLocalAdjustmentCanvasInput
{
    private readonly DevelopLocalAdjustmentSection view;
    private readonly LocalAdjustmentDraft draft = new();
    private LocalDodgeBurnPoint lastBrushPoint;
    private bool hasLastBrushPoint;

    internal DevelopLocalAdjustmentCanvasInput(DevelopLocalAdjustmentSection view) =>
        this.view = view;

    /// <summary>지금 사진 위에 그리는 중인지. 캔버스가 다른 도구보다 먼저 물어봅니다.</summary>
    internal bool IsDrawing => view.FrameId is { } id && view.Session.IsActive(id);

    /// <summary>다각형 꼭짓점이 셋 이상이면 완료 단추가 섭니다.</summary>
    internal bool CanFinishPolygon =>
        IsDrawing &&
        view.Session.MaskKind == LocalDodgeBurnMaskKind.Polygon &&
        view.Session.PolygonPoints.Count >= 3;

    internal bool TryHandlePressed(PointerRoutedEventArgs args, LocalDodgeBurnPoint point)
    {
        if (!IsDrawing)
        {
            return false;
        }
        if (view.Session.MaskKind == LocalDodgeBurnMaskKind.Polygon)
        {
            // macOS 는 다각형만 끌지 않고 누를 때마다 꼭짓점을 찍습니다.
            view.Session.AddPolygonPoint(point);
            view.NotifyPromptChanged();
            args.Handled = true;
            return true;
        }
        draft.Begin(point);
        lastBrushPoint = point;
        hasLastBrushPoint = true;
        args.Handled = true;
        return true;
    }

    internal bool TryHandleMoved(PointerRoutedEventArgs args, LocalDodgeBurnPoint point)
    {
        if (!IsDrawing || !draft.IsDragging)
        {
            return false;
        }
        LocalDodgeBurnMaskKind kind = view.Session.MaskKind;
        // macOS 는 브러시에서 2pt 만큼 움직였을 때만 점을 더 쌓습니다. 화면 픽셀마다 쌓으면
        // 획 하나가 수천 점이 되어 저장도 현상도 무거워집니다.
        bool stepped = kind != LocalDodgeBurnMaskKind.Brush ||
            !hasLastBrushPoint ||
            Distance(lastBrushPoint, point) >= BrushStepInNormalizedUnits;
        draft.Extend(kind, point, stepped);
        if (stepped)
        {
            lastBrushPoint = point;
            hasLastBrushPoint = true;
        }
        args.Handled = true;
        return true;
    }

    internal bool TryHandleReleased(PointerRoutedEventArgs args, LocalDodgeBurnPoint point)
    {
        if (!IsDrawing || !draft.IsDragging)
        {
            return false;
        }
        hasLastBrushPoint = false;
        Commit(draft.End(view.Session.MaskKind, point), view.Session.MaskKind);
        args.Handled = true;
        return true;
    }

    /// <summary>macOS <c>finishPolygon()</c> — 찍어 둔 꼭짓점으로 다각형을 만듭니다.</summary>
    internal void FinishPolygon()
    {
        if (!CanFinishPolygon)
        {
            return;
        }
        Commit(view.Session.PolygonPoints, LocalDodgeBurnMaskKind.Polygon);
        view.Session.ClearPolygonPoints();
    }

    internal void Cancel()
    {
        draft.Cancel();
        hasLastBrushPoint = false;
    }

    /// <summary>
    /// 화면 2pt 를 정규화 좌표로 옮긴 값입니다. 캔버스 크기를 모르는 자리라 macOS 의
    /// 문턱을 화면 폭 1000pt 기준으로 환산해 씁니다 — 점 밀도를 정하는 값일 뿐이라
    /// 마스크 모양은 달라지지 않습니다.
    /// </summary>
    private const double BrushStepInNormalizedUnits = LocalAdjustmentDraft.MinimumBrushStep / 1000.0;

    private void Commit(IReadOnlyList<LocalDodgeBurnPoint> points, LocalDodgeBurnMaskKind kind)
    {
        if (LocalAdjustmentMaskFactory.Make(
                kind,
                points,
                view.Session.BrushThickness,
                view.Session.Feather,
                view.ImageWidth,
                view.ImageHeight) is not { } mask)
        {
            return;
        }
        LocalDodgeBurnAdjustment adjustment = view.Session.MakeAdjustment(mask);
        view.Replace(LocalAdjustmentEditing.Add(view.Adjustments, adjustment));
        view.Session.SelectedAdjustmentId = adjustment.Id;
        view.Show();
        view.NotifyPromptChanged();
    }

    private static double Distance(LocalDodgeBurnPoint start, LocalDodgeBurnPoint end)
    {
        double dx = start.X - end.X;
        double dy = start.Y - end.Y;
        return Math.Sqrt((dx * dx) + (dy * dy));
    }
}
