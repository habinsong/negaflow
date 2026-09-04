using Negaflow.Catalog;

namespace Negaflow.Shell.Develop;

/// <summary>
/// 한 Develop 작업공간의 크롭 세션·드래그·종횡비 잠금만 소유합니다. 미리보기 렌더,
/// GrainMend, 내보내기와 다른 변경 이유를 가지므로 뷰 밖에 둡니다.
/// </summary>
public sealed class CropWorkspaceState
{
    public CropSession? Session { get; private set; }

    public CropDragMode DragMode { get; private set; }

    public CropDisplayPoint DragStart { get; private set; }

    public CropDisplayRect DragStartRect { get; private set; }

    public bool AwaitingPreview { get; private set; }

    /// <summary>
    /// 현재 화면에 그려진 크롭 오버레이의 프레임입니다. **사진이 놓이는 프레임이 바뀔 때마다**
    /// 갱신합니다 - 줌·팬·캔버스 크기·새 미리보기 전부입니다. macOS 는 캐시 없이
    /// `canvasFittedImageFrame(..., scale:offset:)` 하나를 사진과 크롭에 똑같이 넘깁니다
    /// (`CanvasView.swift`). 여기서 값을 들고 있는 것은 그 사이 - 포인터 드래그 중에 미리보기가
    /// 다시 와도 오버레이가 흔들리지 않게 하기 위해서일 뿐이며, **줌·팬을 무시하라는 뜻이
    /// 아닙니다.** 무시했더니 확대하면 크롭이 사진 안쪽으로 들어가고 축소하면 사진보다 넓게
    /// 잡혔습니다.
    /// </summary>
    public PreviewFrame? OverlayFrame { get; private set; }

    /// <summary>macOS 의 <c>crop.aspectLocked</c> 와 같이 잠긴 상태로 시작합니다.</summary>
    public bool IsAspectLocked { get; private set; } = true;

    public bool IsActive => Session is not null;

    public bool CanInteract => Session is not null && !AwaitingPreview;

    public bool IsDragging => DragMode != CropDragMode.None;

    /// <summary>
    /// 세션을 열 때의 종횡비입니다. 취소는 사각형만이 아니라 <b>이 값도</b> 되돌립니다 —
    /// 크롭 화면 안에서 고른 비율은 크롭 화면 안에서 한 일이기 때문입니다.
    /// </summary>
    /// <remarks>
    /// 앞 판은 사각형만 되돌렸습니다. 그래서 "진입 → 3:2 → 자르지 않고 취소 → 다시 진입"
    /// 하면 비율 고르개는 3:2 라고 적혀 있는데 사각형은 전체인, 서로 어긋난 상태가
    /// 남았습니다(사용자 보고 2026-09-04).
    /// </remarks>
    private double? previousAspect;

    public CropSession? Begin(
        ImageCropRect? currentCrop,
        double? currentAspect,
        double? lockedNormalizedAspect)
    {
        CropSession next = CropSession.Start(currentCrop);
        next.LockedNormalizedAspectRatio = lockedNormalizedAspect;
        Session = next;
        previousAspect = currentAspect;
        DragMode = CropDragMode.None;
        AwaitingPreview = true;
        OverlayFrame = null;
        return next;
    }

    public void MarkPreviewReady()
    {
        AwaitingPreview = false;
    }

    public void End()
    {
        Session = null;
        previousAspect = null;
        DragMode = CropDragMode.None;
        AwaitingPreview = false;
        OverlayFrame = null;
    }

    public void SetOverlayFrame(PreviewFrame frame)
    {
        if (IsActive && frame.Width > 0.0 && frame.Height > 0.0)
        {
            OverlayFrame = frame;
        }
    }

    public ImageCropRect? Cancel()
    {
        return Session?.Cancel();
    }

    /// <summary>취소가 되돌릴 종횡비입니다. 세션이 없으면 되돌릴 것도 없습니다.</summary>
    public double? CancelAspect() => Session is null ? null : previousAspect;

    public ImageCropRect? Apply()
    {
        return Session?.Apply();
    }

    public bool Full()
    {
        if (Session is null)
        {
            return false;
        }

        Session.Full();
        return true;
    }

    public bool ToggleAspectLock()
    {
        IsAspectLocked = !IsAspectLocked;
        return IsAspectLocked;
    }

    public void SyncLockedAspect(double? lockedNormalizedAspect)
    {
        if (Session is not null)
        {
            Session.LockedNormalizedAspectRatio = lockedNormalizedAspect;
        }
    }

    public bool TryBeginDrag(CropDisplayPoint point) =>
        TryBeginDrag(point, 0.0, 0.0, allowCreate: true);

    /// <summary>
    /// 누른 자리에서 드래그를 시작합니다. 프레임 크기를 주면 핸들 히트 영역이 <b>그려진
    /// 핸들과 같아집니다</b>. <paramref name="allowCreate"/> 가 거짓이면 핸들을 잡았을
    /// 때만 시작합니다 — 그림 밖을 눌러 새 사각형이 그려지지 않게 합니다.
    /// </summary>
    public bool TryBeginDrag(
        CropDisplayPoint point,
        double frameWidth,
        double frameHeight,
        bool allowCreate)
    {
        if (!CanInteract || Session is null)
        {
            return false;
        }

        CropDisplayRect rect = Session.Selection;
        CropDragMode mode = CropInteraction.BeginDrag(point, rect, frameWidth, frameHeight);
        if (!allowCreate && mode is CropDragMode.Create or CropDragMode.Move)
        {
            return false;
        }

        DragStart = point;
        DragStartRect = rect;
        DragMode = mode;
        if (Negaflow.Shell.PreviewTrace.IsEnabled)
        {
            string unit = System.FormattableString.Invariant($"({point.X:F4},{point.Y:F4})");
            string box = System.FormattableString.Invariant(
                $"({DragStartRect.X:F4},{DragStartRect.Y:F4},{DragStartRect.Width:F4},{DragStartRect.Height:F4})");
            string lockedAspect = Session.LockedNormalizedAspectRatio is { } ratio
                ? ratio.ToString("F4", System.Globalization.CultureInfo.InvariantCulture)
                : "none";
            Negaflow.Shell.PreviewTrace.Write(
                "crop.begin unit=" + unit + " rect=" + box +
                " mode=" + DragMode + " lockedAspect=" + lockedAspect);
        }
        return true;
    }

    public bool TryContinueDrag(CropDisplayPoint point)
    {
        if (!CanInteract || !IsDragging || Session is null)
        {
            return false;
        }

        switch (DragMode)
        {
            case CropDragMode.Create:
                Session.Select(DragStart, point);
                break;
            case CropDragMode.Move:
                Session.SetSelection(DragStartRect.Move(
                    point.X - DragStart.X,
                    point.Y - DragStart.Y));
                break;
            default:
                if (CropInteraction.HandleFor(DragMode) is { } handle)
                {
                    Session.SetSelection(DragStartRect.Resize(handle, point));
                }
                break;
        }

        if (Negaflow.Shell.PreviewTrace.IsEnabled)
        {
            CropDisplayRect now = Session.Selection;
            string shape = System.FormattableString.Invariant(
                $"({now.X:F4},{now.Y:F4},{now.Width:F4},{now.Height:F4}) ratio={now.Width / Math.Max(1e-9, now.Height):F4}");
            Negaflow.Shell.PreviewTrace.Write("crop.drag " + DragMode + " rect=" + shape);
        }
        return true;
    }

    public bool EndDrag()
    {
        if (!IsDragging)
        {
            return false;
        }

        DragMode = CropDragMode.None;
        return true;
    }

    public bool TryMove(double dx, double dy)
    {
        if (Session is null)
        {
            return false;
        }

        Session.Move(dx, dy);
        return true;
    }
}
