using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views;

/// <summary>
/// 필름 베이스 스포이드입니다.
/// </summary>
/// <remarks>
/// macOS <c>pickFilmBase(at:)</c> 자리입니다. 집는 동안에는 반전 전 화소를 봐야 하므로
/// <c>UninvertedSource</c> 를 켜고, 다 집으면 되돌립니다.
/// </remarks>
public sealed partial class DevelopWorkspaceView
{
    /// <summary>
    /// macOS <c>handleBasePick(atDisplayUnit:)</c> — 스포이드가 켜져 있을 때의 캔버스 클릭입니다.
    /// 표시 정규 좌표를 원본 정규로 되돌린 뒤 <c>FilmBasePicker.sample</c> 에 넘기고, 성립하는
    /// 값만 수동 Dmin 으로 앉힙니다. 성립하지 않으면 <b>Dmin 을 바꾸지 않고</b> 안내만 냅니다 —
    /// 필름 밖 검정 띠가 Dmin 이 되면 반전이 전 구간 클리핑되어 사진이 통째로 검게 죽습니다.
    /// </summary>
    private bool TryHandleBasePick(Microsoft.UI.Xaml.Input.PointerRoutedEventArgs args)
    {
        if (!BaseCard.IsBasePickerActive ||
            panel?.SelectedFrame is not { SourceMetadata: { } metadata } frame ||
            frame.SourcePath is not { Length: > 0 } sourcePath ||
            !PreviewCanvas.TryMapPointer(args, out CropDisplayPoint point))
        {
            return false;
        }
        args.Handled = true;
        // macOS 도 픽셀 샘플러와 같이 baseSize 를 넘겨 미세 회전 역변환까지 정확히 풉니다.
        if (!DevelopDisplayGeometry.TryMapDisplayToRaw(
                frame.ImageTransform,
                metadata.PixelWidth,
                metadata.PixelHeight,
                point.X,
                point.Y,
                out double rawX,
                out double rawY))
        {
            return true;
        }

        bool monochrome = frame.Route.FilmType is FilmType.BlackAndWhiteNegative;
        // macOS `pickFilmBase` 는 `Task.detached` 로 샘플합니다. WIC 디코더는
        // COINIT_MULTITHREADED 를 요구하는데 WinUI 스레드는 STA 라서, 여기서 직접
        // 열면 `RPC_E_CHANGED_MODE` 로 디코드가 실패하고 Dmin 이 그대로입니다.
        string path = sourcePath;
        double unitX = rawX;
        double unitY = rawY;
        Microsoft.UI.Dispatching.DispatcherQueue queue = DispatcherQueue;
        basePickInFlight = true;
        BaseCard.CancelBasePicker();
        PreviewCanvas.ShowBasePickerPrompt(false);
        _ = System.Threading.Tasks.Task.Run(() =>
        {
            FilmBasePick picked;
            try
            {
                picked = FilmBasePick.Sample(path, unitX, unitY, monochrome);
            }
            catch
            {
                picked = new FilmBasePick(FilmBasePickOutcome.SourceUnavailable, 0.0, 0.0, 0.0);
            }
            _ = queue.TryEnqueue(() => ApplyPickedFilmBase(picked));
        });
        return true;
    }

    private void ApplyPickedFilmBase(FilmBasePick picked)
    {
        try
        {
            if (picked.Outcome != FilmBasePickOutcome.Picked || panel is null)
            {
                ExportStatusText.Text = AppResources.Get(
                    picked.Outcome == FilmBasePickOutcome.NotFilmBase
                        ? "developBasePickNotFilmBase"
                        : "developBasePickFailed",
                    "Text");
                RequestPreview();
                return;
            }
            if (panel.SetManualBase(picked.Red, picked.Green, picked.Blue) != LibraryFrameError.None)
            {
                RequestPreview();
                return;
            }
            ExportStatusText.Text = string.Empty;
            BaseCard.ShowManualValues(panel);
            BaseCard.Sync();
            RequestPreview();
        }
        finally
        {
            basePickInFlight = false;
        }
    }

    /// <summary>macOS <c>resetManualBase</c> — 수동 Dmin 을 제안값으로 되돌립니다.</summary>
    private void ResetManualBase()
    {
        if (panel is null)
        {
            return;
        }
        double suggested = panel.SuggestedManualDmin;
        if (panel.SetManualBase(suggested, suggested, suggested) != LibraryFrameError.None)
        {
            return;
        }
        BaseCard.ShowManualValues(panel);
        BaseCard.Sync();
        RequestPreview();
    }
}
