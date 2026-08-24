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
            view.panel.ImageTransform.Rotation,
            // 고른 비율이 없으면 지금 사각형의 비율을 잠급니다(macOS 와 같음).
            view.crop.Session?.Selection);
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

    internal void ToggleFromMenu() => Toggle();

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

        // macOS처럼 기존 crop을 먼저 보관한 뒤 원본 전체를 보여 줍니다. 앞 판은 SetCrop(null)
        // 뒤에 값을 읽어 세션이 늘 전체 사각형으로 시작했고, 내부 drag가 새 선택 생성으로
        // 잘못 들어갔습니다.
        ImageCropRect? previousCrop = view.panel.ImageTransform.Crop;
        if (view.panel.SetCrop(null) != LibraryFrameError.None)
        {
            return;
        }
        view.crop.Begin(previousCrop, lockedNormalizedAspect: null);
        view.crop.SyncLockedAspect(LockedNormalizedAspectRatio());
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
        // macOS `applyCrop` → `resetViewport()`.
        view.panel.Viewport.Reset();
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
