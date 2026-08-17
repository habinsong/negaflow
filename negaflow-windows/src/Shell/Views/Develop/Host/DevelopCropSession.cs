using Microsoft.UI.Xaml;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;

namespace Negaflow.Shell.Views.Develop.Host;

/// <summary>크롭 세션 시작·적용·취소입니다. 캔버스 오버레이 배치와 다른 이유입니다.</summary>
internal sealed class DevelopCropSession
{
    private readonly DevelopWorkspaceView view;

    internal DevelopCropSession(DevelopWorkspaceView view) => this.view = view;

    internal void Hook()
    {
        view.GeometryCard.CropClicked += OnGeometryCropClicked;
        view.PreviewCanvas.CropApplyRequested += OnApplyClicked;
        view.PreviewCanvas.CropCancelRequested += OnCancelClicked;
        view.PreviewCanvas.CropFullRequested += OnFullClicked;
    }

    internal void Cancel()
    {
        if (!view.crop.IsActive)
        {
            return;
        }
        ImageCropRect? restore = view.crop.Cancel();
        if (view.panel?.SetCrop(restore) != LibraryFrameError.None)
        {
            return;
        }
        End();
        view.RequestPreview();
    }

    internal void End()
    {
        view.crop.End();
        view.PreviewCanvas.HideCropOverlay();
        view.GeometryCard.SetDialVisible(false);
    }

    internal double? LockedNormalizedAspectRatio()
    {
        if (view.panel?.SelectedFrame is not { SourceMetadata: { } metadata })
        {
            return null;
        }
        return CropInteraction.LockedNormalizedAspectRatio(
            view.crop.IsAspectLocked,
            view.panel.ImageTransform.CropAspect,
            metadata.PixelWidth,
            metadata.PixelHeight,
            view.panel.ImageTransform.Rotation);
    }

    internal void OnAspectChosen(object? sender, CropAspectOption option)
    {
        _ = sender;
        // 비율이 crop 을 다시 만드는 동안에는 진행 중인 crop session 을 접습니다 — 두 곳이
        // 같은 사각형을 서로 다르게 들고 있으면 Apply 가 어느 쪽을 쓸지 알 수 없습니다.
        Cancel();
        view.UpdateImageTransform(state => state.SetCropAspect(option));
    }

    internal void OnAspectLockToggled(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        bool nextLocked = view.crop.ToggleAspectLock();
        // 잠금은 catalog 가 아니라 다음 crop 드래그의 동작만 바꿉니다.
        view.GeometryCard.SetLockGlyph(nextLocked);
        view.crop.SyncLockedAspect(LockedNormalizedAspectRatio());
        if (view.panel is not null)
        {
            view.GeometryCard.UpdateAspectControls(view.panel, view.crop.IsAspectLocked);
        }
    }

    private void OnGeometryCropClicked(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        Toggle();
    }

    private void Toggle()
    {
        if (view.crop.IsActive)
        {
            Cancel();
            return;
        }
        if (view.panel is null || view.panel.SelectedFrame is null || !view.PreviewCanvas.HasPreview)
        {
            return;
        }

        // macOS와 같이 crop을 먼저 해제해 전체 프레임에서 새 선택을 만들게 합니다. 드래그 중
        // catalog를 쓰지 않고 Apply/Cancel에서 한 번만 저장합니다.
        if (view.panel.SetCrop(null) != LibraryFrameError.None)
        {
            return;
        }
        view.crop.Begin(view.panel.ImageTransform.Crop, LockedNormalizedAspectRatio());
        view.GeometryCard.SetDialVisible(true);
        view.PreviewCanvas.FocusHost();
        view.RequestPreview();
    }

    private void OnApplyClicked(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        if (!view.crop.IsActive || view.panel is null)
        {
            return;
        }
        if (view.panel.SetCrop(view.crop.Apply()) != LibraryFrameError.None)
        {
            return;
        }
        End();
        view.RequestPreview();
    }

    private void OnFullClicked(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        if (!view.crop.Full())
        {
            return;
        }
        view.PreviewCanvas.RenderCropOverlay();
    }

    private void OnCancelClicked(object? sender, EventArgs args)
    {
        _ = sender;
        _ = args;
        Cancel();
    }
}
