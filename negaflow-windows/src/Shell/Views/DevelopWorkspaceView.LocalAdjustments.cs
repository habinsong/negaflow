using Microsoft.UI.Xaml.Input;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell.Views;

/// <summary>포인터가 어느 단계로 들어왔는지입니다.</summary>
internal enum LocalPointerPhase
{
    Pressed,
    Moved,
    Released,
}

/// <summary>
/// 부분 보정 그리기를 캔버스에 잇습니다.
/// </summary>
/// <remarks>
/// macOS <c>LocalAdjustmentOverlay</c> 는 그리기가 켜져 있을 때만 제스처 층을 깔고, 켤 때
/// 크롭·브러시·결함·복제 도장·베이스 스포이드를 모두 끕니다. 여기서도 같은 순서입니다 —
/// 켜져 있으면 이쪽이 먼저 포인터를 먹고, 켤 때 다른 도구를 내립니다.
/// </remarks>
public sealed partial class DevelopWorkspaceView
{
    private bool TryHandleLocalAdjustment(PointerRoutedEventArgs args, LocalPointerPhase phase)
    {
        if (!LocalAdjustmentCard.CanvasInput.IsDrawing ||
            !PreviewCanvas.TryMapPointer(args, out CropDisplayPoint mapped))
        {
            return false;
        }
        LocalDodgeBurnPoint point = new(mapped.X, mapped.Y);
        bool handled = phase switch
        {
            LocalPointerPhase.Pressed =>
                LocalAdjustmentCard.CanvasInput.TryHandlePressed(args, point),
            LocalPointerPhase.Moved =>
                LocalAdjustmentCard.CanvasInput.TryHandleMoved(args, point),
            _ => LocalAdjustmentCard.CanvasInput.TryHandleReleased(args, point),
        };
        if (handled && phase == LocalPointerPhase.Pressed)
        {
            PreviewCanvas.CaptureHost(args.Pointer);
        }
        return handled;
    }

    /// <summary>
    /// macOS <c>toggleDrawing(_:)</c> 이 켤 때 하는 일 — 다른 캔버스 도구를 모두 내립니다.
    /// </summary>
    private void OnLocalAdjustmentDrawingToggled(object? sender, bool drawing)
    {
        _ = sender;
        if (!drawing)
        {
            return;
        }
        ExitCanvasToolsForLocalAdjustment();
    }

    /// <summary>
    /// 안내 캡슐을 지금 상태에 맞춥니다. 종류 아이콘과 다각형 완료 단추가 따라갑니다.
    /// </summary>
    internal void SyncLocalAdjustmentPrompt() => PreviewCanvas.ShowLocalAdjustmentPrompt(
        LocalAdjustmentCard.CanvasInput.IsDrawing,
        LocalMaskGlyph(LocalAdjustmentCard.Session.MaskKind),
        LocalAdjustmentCard.CanvasInput.CanFinishPolygon);

    /// <summary>목록 줄과 같은 글리프를 씁니다 — 같은 것에 다른 그림을 쓰지 않습니다.</summary>
    private static string LocalMaskGlyph(LocalDodgeBurnMaskKind kind) => kind switch
    {
        LocalDodgeBurnMaskKind.Radial => "\uECCA",
        LocalDodgeBurnMaskKind.Linear => "\uF246",
        LocalDodgeBurnMaskKind.Polygon => "\uE754",
        _ => "\uE790",
    };
}
