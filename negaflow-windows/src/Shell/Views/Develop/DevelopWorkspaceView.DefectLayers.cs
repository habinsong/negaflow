using System.IO;
using System.Runtime.InteropServices.WindowsRuntime;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media.Imaging;
using Negaflow.Catalog;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;
using Negaflow.Shell.Views.Controls;

namespace Negaflow.Shell.Views;

/// <summary>
/// GrainMend 레이어 목록의 배선입니다. macOS <c>DefectLayerSection</c> 이 <c>AppModel</c> 의
/// 어느 함수를 부르는지에 대응하는 자리이며, 캔버스·검출·내보내기와 다른 이유로 바뀌므로
/// 여기 따로 둡니다.
/// </summary>
public sealed partial class DevelopWorkspaceView
{
    /// <summary>
    /// 목록을 다시 그립니다. 고른 사진이 바뀌거나, 항목이 늘거나 줄거나, 켜짐·강도가 바뀔 때
    /// 부릅니다.
    /// </summary>
    private void UpdateDefectLayers()
    {
        if (DefectLayers is null || panel is null)
        {
            return;
        }
        panel.DefectLayers.ForgetMissingMaskPreview();
        DefectLayerSectionState state = DefectLayerProjection.Create(
            panel.SelectedFrame,
            DefectLayerTextFactory.Create(),
            panel.DefectLayers.MaskPreviewId,
            // 검토 완료 기록은 아직 카탈로그에 없습니다. 없는 것을 있는 것처럼 내지 않고,
            // 언제나 "아직 완료하지 않음"으로 냅니다.
            reviewed: null,
            grainMend.IsDetecting);
        DefectLayers.Update(state, DefectLayerTextFactory.Create(), grainMend.IsDetecting);
        ShowDefectMaskOverlay();
    }

    private void OnDefectLayerCommand(object? sender, DefectLayerCommandEventArgs args)
    {
        _ = sender;
        if (panel is null)
        {
            return;
        }
        switch (args.Command)
        {
            case DefectLayerCommand.ToggleEnabled:
                Apply(panel.DefectLayers.SetEnabled(args.Id, !IsLayerEnabled(args.Id)));
                break;
            case DefectLayerCommand.Delete:
                Apply(panel.DefectLayers.Remove(args.Id));
                break;
            case DefectLayerCommand.ToggleMask:
                panel.DefectLayers.ToggleMaskPreview(args.Id);
                UpdateDefectLayers();
                break;
            case DefectLayerCommand.SetStrength:
                SetLayerStrength(args);
                break;
            case DefectLayerCommand.MarkReviewed:
                // 저장할 자리가 아직 없습니다. 되는 척하지 않고 아무 일도 하지 않습니다.
                break;
            default:
                break;
        }
    }

    /// <summary>
    /// 끄는 동안에는 미리보기만 다시 그리고 목록은 건드리지 않습니다 — 목록을 다시 만들면
    /// 슬라이더가 새로 붙어 드래그가 끊깁니다. 놓을 때 한 번만 저장합니다.
    /// </summary>
    private void SetLayerStrength(DefectLayerCommandEventArgs args)
    {
        if (panel is null ||
            panel.DefectLayers.SetStrength(args.Id, args.Strength, args.IsLive) !=
                LibraryFrameError.None)
        {
            return;
        }
        if (args.IsLive)
        {
            RequestPreview();
            return;
        }
        UpdateDefectLayers();
        RequestPreview();
    }

    /// <summary>
    /// 고른 레이어의 마스크를 캔버스에 덮습니다. 검토 중인 후보 덮개와 같은 <c>Image</c> 를
    /// 쓰므로, 검토가 진행 중이면 그쪽을 건드리지 않습니다 — 두 덮개가 한 자리를 다투면
    /// 나중 것만 보이고 사용자는 어느 쪽을 보고 있는지 알 수 없습니다.
    /// </summary>
    private void ShowDefectMaskOverlay()
    {
        if (panel is null || DefectOverlayImage is null || grainMend.PendingEdit is not null)
        {
            return;
        }
        if (panel.DefectLayers.MaskPreviewId is not { } id ||
            panel.SelectedFrame is not { } frame ||
            previewBitmap is null ||
            panel.DefectLayers.Items.FirstOrDefault(item => item.Id == id) is not { } item)
        {
            HideDefectOverlay();
            return;
        }

        int width = previewBitmap.PixelWidth;
        int height = previewBitmap.PixelHeight;
        if (DefectMaskOverlayRenderer.Render(frame, width, height, item) is not { } bgra)
        {
            HideDefectOverlay();
            return;
        }
        WriteableBitmap bitmap = new(width, height);
        using (Stream buffer = bitmap.PixelBuffer.AsStream())
        {
            buffer.Write(bgra, 0, bgra.Length);
        }
        bitmap.Invalidate();
        DefectOverlayImage.Source = bitmap;
        DefectOverlayImage.Visibility = Visibility.Visible;
    }

    private bool IsLayerEnabled(Guid id) =>
        panel?.DefectLayers.Items.FirstOrDefault(item => item.Id == id)?.Enabled == true;

    private void Apply(LibraryFrameError error)
    {
        if (error != LibraryFrameError.None)
        {
            return;
        }
        // UpdateGrainMendCard 가 끝에서 목록도 다시 그립니다.
        UpdateGrainMendCard();
        RequestPreview();
    }
}
