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

    /// <summary>macOS 의 <c>crop.aspectLocked</c> 와 같이 잠긴 상태로 시작합니다.</summary>
    public bool IsAspectLocked { get; private set; } = true;

    public bool IsActive => Session is not null;

    public bool CanInteract => Session is not null && !AwaitingPreview;

    public bool IsDragging => DragMode != CropDragMode.None;

    public CropSession? Begin(ImageCropRect? currentCrop, double? lockedNormalizedAspect)
    {
        CropSession next = CropSession.Start(currentCrop);
        next.LockedNormalizedAspectRatio = lockedNormalizedAspect;
        Session = next;
        DragMode = CropDragMode.None;
        AwaitingPreview = true;
        return next;
    }

    public void MarkPreviewReady()
    {
        AwaitingPreview = false;
    }

    public void End()
    {
        Session = null;
        DragMode = CropDragMode.None;
        AwaitingPreview = false;
    }

    public ImageCropRect? Cancel()
    {
        return Session?.Cancel();
    }

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
