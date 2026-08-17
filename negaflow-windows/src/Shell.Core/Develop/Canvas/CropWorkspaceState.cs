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

    public bool TryBeginDrag(CropDisplayPoint point)
    {
        if (!CanInteract || Session is null)
        {
            return false;
        }

        DragStart = point;
        DragStartRect = Session.Selection;
        DragMode = CropInteraction.BeginDrag(point, DragStartRect);
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
