using System.IO;
using System.Runtime.InteropServices.WindowsRuntime;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media.Imaging;

namespace Negaflow.Shell.Views.Develop.Canvas;

/// <summary>
/// 검출·마스크 덮개 화소를 미리보기 위에 올립니다. 마스크 계산은 뷰가 맡습니다.
/// </summary>
internal sealed class DevelopCanvasDefectOverlay
{
    private readonly DevelopPreviewCanvas view;
    private WriteableBitmap? bitmap;

    internal DevelopCanvasDefectOverlay(DevelopPreviewCanvas view) => this.view = view;

    internal void Hide()
    {
        view.DefectOverlayImage.Source = null;
        view.DefectOverlayImage.Visibility = Visibility.Collapsed;
    }

    internal void Show(byte[] bgra, int width, int height)
    {
        // 크기가 바뀔 때만 새로 만듭니다 — 미리보기(`Present`)와 같은 규칙입니다. 복제 도장과
        // 브러시 커서는 포인터가 움직일 <b>때마다</b> 이 표면을 다시 그리므로, 매번 새로
        // 만들면 1600×1200 에서 손을 젓는 동안 7.7MB 를 프레임마다 버립니다.
        if (bitmap is null || bitmap.PixelWidth != width || bitmap.PixelHeight != height)
        {
            bitmap = new WriteableBitmap(width, height);
        }
        using (Stream buffer = bitmap.PixelBuffer.AsStream())
        {
            buffer.Write(bgra, 0, bgra.Length);
        }
        bitmap.Invalidate();
        view.DefectOverlayImage.Source = bitmap;
        view.DefectOverlayImage.Visibility = Visibility.Visible;
    }
}
