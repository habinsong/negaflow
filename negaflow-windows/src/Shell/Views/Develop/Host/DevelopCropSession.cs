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
        if (view.panel is not { } panel)
        {
            return;
        }

        // 크롭 화면이 닫혀 있으면 그냥 비율과 사각형을 함께 적습니다.
        if (!view.crop.IsActive)
        {
            view.UpdateImageTransform(state => state.SetCropAspect(option));
            TraceAspect(option, "크롭 밖");
            return;
        }

        // **크롭 중에는 자르지 않은 원본을 보여 줍니다.**
        //
        // 예전에는 여기서 `Cancel()` 을 불러 하던 크롭이 사라졌고, 그것을 고친 뒤에는
        // 사각형까지 함께 적어 미리보기가 잘린 그림으로 바뀌었습니다. 그러면 다음 비율이
        // 그 잘린 그림 위에 다시 걸립니다. 실측 2026-08-30 15:17, 4:3 다음에 2:3 을
        // 고르자 화면에 그려지던 그림의 비율이 이미 1.333 이었고, 결과가 두 비율을 겹친
        // 모양이 됐습니다.
        //
        // 그래서 비율만 적고, 사각형은 세션의 선택으로만 옮깁니다. 카탈로그에는 사용자가
        // 적용을 누를 때 `CropSession.Apply` 가 씁니다. macOS 도 크롭 화면에서는 자르지
        // 않은 현상본을 그리고 사각형은 오버레이로만 둡니다.
        ImageTransformRecipe shaped = CropAspect.Apply(
            panel.ImageTransform with { Crop = null },
            option,
            panel.SelectedFrame?.SourceMetadata?.PixelWidth ?? 0U,
            panel.SelectedFrame?.SourceMetadata?.PixelHeight ?? 0U);
        view.UpdateImageTransform(state => state.SetCropAspectOnly(option));
        TraceAspect(option, "고른 직후");

        // 잠긴 비율을 먼저 갱신합니다. 뒤에 하면 새 사각형에 옛 비율이 한 번 더 씌워집니다.
        view.crop.SyncLockedAspect(LockedNormalizedAspectRatio());
        if (view.crop.Session is { } session)
        {
            session.SetSelectionExact(shaped.Crop is { } crop
                ? new CropDisplayRect(
                    crop.X,
                    1.0 - (crop.Y + crop.Height),
                    crop.Width,
                    crop.Height)
                : CropDisplayRect.Full);
        }
        view.GeometryCard.UpdateAspectControls(panel, view.crop.IsAspectLocked);
        view.PreviewCanvas.RenderCropOverlay();
        TraceAspect(option, "세션 반영 뒤");
    }

    /// <summary>비율을 고를 때 실제로 쓰인 값을 남깁니다. 화면만 재서는 어디가 어긋났는지
    /// 가릴 수 없습니다.</summary>
    private void TraceAspect(CropAspectOption option, string phase)
    {
        if (view.panel is not { } panel)
        {
            return;
        }
        ImageTransformRecipe transform = panel.ImageTransform;
        uint pixelWidth = panel.SelectedFrame?.SourceMetadata?.PixelWidth ?? 0U;
        uint pixelHeight = panel.SelectedFrame?.SourceMetadata?.PixelHeight ?? 0U;
        double displayWidth = pixelWidth;
        double displayHeight = pixelHeight;
        if (transform.Rotation is ImageRotation.Degrees90 or ImageRotation.Degrees270)
        {
            (displayWidth, displayHeight) = (displayHeight, displayWidth);
        }
        static string Fixed(double value) =>
            value.ToString("F4", System.Globalization.CultureInfo.InvariantCulture);
        string crop = transform.Crop is { } box
            ? "(" + Fixed(box.X) + "," + Fixed(box.Y) + "," +
                Fixed(box.Width) + "," + Fixed(box.Height) + ")"
            : "none";
        string selection = view.crop.Session is { } session
            ? "(" + Fixed(session.Selection.X) + "," + Fixed(session.Selection.Y) + "," +
                Fixed(session.Selection.Width) + "," + Fixed(session.Selection.Height) + ")"
            : "none";
        double selectionRatio = view.crop.Session is { } shown &&
            shown.Selection.Height > 0.0 && displayHeight > 0.0
            ? shown.Selection.Width * displayWidth / (shown.Selection.Height * displayHeight)
            : 0.0;
        double cropRatio = transform.Crop is { } stored && stored.Height > 0.0 && displayHeight > 0.0
            ? stored.Width * displayWidth / (stored.Height * displayHeight)
            : 0.0;
        double overlayRatio = view.crop.OverlayFrame is { } overlay && overlay.Height > 0.0
            ? overlay.Width / overlay.Height
            : 0.0;
        CropTrace.Write(
            phase + " 고른값=" + option.Label + "(" + Fixed(option.Ratio ?? -99.0) + ")" +
            " 원본=" + pixelWidth.ToString(System.Globalization.CultureInfo.InvariantCulture) + "x" +
                pixelHeight.ToString(System.Globalization.CultureInfo.InvariantCulture) +
            " rot=" + transform.Rotation +
            " 표시=" + Fixed(displayWidth) + "x" + Fixed(displayHeight) +
            " 오버레이비율=" + Fixed(overlayRatio) +
            " cropAspect=" + Fixed(transform.CropAspect ?? -99.0) +
            " crop=" + crop + " cropPixelRatio=" + Fixed(cropRatio) +
            " selection=" + selection + " selectionPixelRatio=" + Fixed(selectionRatio) +
            " lock=" + view.crop.IsAspectLocked +
            " lockedNorm=" + Fixed(LockedNormalizedAspectRatio() ?? -99.0));
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
