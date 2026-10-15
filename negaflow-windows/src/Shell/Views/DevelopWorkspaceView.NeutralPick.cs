using Negaflow.Catalog;
using Negaflow.Interop;
using Negaflow.Shell.Develop;
using Negaflow.Shell.Localization;

namespace Negaflow.Shell.Views;

/// <summary>
/// 중립 화이트밸런스 스포이드입니다.
/// </summary>
/// <remarks>
/// macOS <c>pickNeutralWhiteBalance(at:frame:)</c> 자리입니다. 현상본을 보며 찍고, 값은 화면 정착
/// 프리뷰와 같은 입력의 화이트밸런스 입력(색 모델 직전)에서 잽니다 — 지금 색온도·틴트와 무관하게
/// 같은 점은 같은 답입니다. 베이스 스포이드와 캔버스 도구 자리를 나눠 씁니다(한쪽을 켜면 다른 쪽이
/// 꺼집니다).
/// </remarks>
public sealed partial class DevelopWorkspaceView
{
    private bool TryHandleNeutralPick(Microsoft.UI.Xaml.Input.PointerRoutedEventArgs args)
    {
        if (!Adjustments.Color.IsNeutralPickerActive ||
            panel?.SelectedFrame is not { SourceMetadata: { } metadata } frame ||
            frame.SourcePath is not { Length: > 0 } ||
            !PreviewCanvas.TryMapPointer(args, out CropDisplayPoint point))
        {
            return false;
        }
        args.Handled = true;
        // 베이스 스포이드와 같은 역변환입니다 — 미세 회전까지 원본 정규 좌표로 되돌립니다.
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

        DevelopRequestResult request = DevelopRequestFactory.Create(frame, frame.SourcePath);
        if (request.Request is not { } input) { return true; }
        // macOS 도 한 번 찍으면 스포이드를 끕니다.
        Adjustments.Color.CancelNeutralPicker();
        // WIC 디코더는 MTA 를 요구합니다 — UI(STA) 스레드에서 직접 열지 않습니다(베이스 스포이드와 같음).
        Microsoft.UI.Dispatching.DispatcherQueue queue = DispatcherQueue;
        _ = System.Threading.Tasks.Task.Run(() =>
        {
            NeutralWhiteBalancePick picked;
            try
            {
                picked = NeutralWhiteBalancePick.Sample(input, rawX, rawY);
            }
            catch
            {
                picked = new NeutralWhiteBalancePick(NeutralWhiteBalancePickOutcome.Unavailable, 0.0, 0.0);
            }
            _ = queue.TryEnqueue(() =>
            {
                // 재는 동안 사진이나 그 입력이 바뀌었으면 버립니다(macOS 의 같은 확인).
                if (panel?.SelectedFrame is not { } current || current.Id != frame.Id ||
                    current.SourcePath != frame.SourcePath || current.SourceMetadata != frame.SourceMetadata ||
                    current.InputGamma != frame.InputGamma || current.Route.FilmType != frame.Route.FilmType ||
                    current.DefectRecipe?.RecipeRevision != frame.DefectRecipe?.RecipeRevision ||
                    current.DefectRecipe?.RecipeSha256 != frame.DefectRecipe?.RecipeSha256)
                {
                    return;
                }
                ApplyPickedNeutral(picked);
            });
        });
        return true;
    }

    private void ApplyPickedNeutral(NeutralWhiteBalancePick picked)
    {
        if (panel is null)
        {
            return;
        }
        if (picked.Outcome != NeutralWhiteBalancePickOutcome.Picked)
        {
            ExportStatusText.Text = AppResources.Get("developNeutralPickFailed", "Text");
            return;
        }
        if (panel.Tone.ApplyNeutralWhiteBalance(picked.Warmth, picked.Tint) != LibraryFrameError.None)
        {
            return;
        }
        ColorModelRecipe applied = panel.Color.ColorModel;
        ExportStatusText.Text = DevelopBaseReadout.FormatValues(
            AppResources.Get("developNeutralPickedFormat", "Text"),
            applied.Warmth,
            applied.Tint);
        SynchronizeInspectorValues();
        RequestPreviewReplacingCurrent();
    }

    /// <summary>Esc — 중립 스포이드가 켜져 있으면 끕니다.</summary>
    internal bool TryExitNeutralPicker()
    {
        if (!Adjustments.Color.IsNeutralPickerActive)
        {
            return false;
        }
        Adjustments.Color.CancelNeutralPicker();
        return true;
    }
}
